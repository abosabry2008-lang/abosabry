import { Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { documentTotals, lineTotals, round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { getSettings, isTaxEnabled } from '../../lib/settings';
import { ACCOUNT, postJournal, type JournalLineInput } from '../accounting/accounting.service';

export const invoiceInclude = {
  customer: { select: { id: true, name: true, email: true, phone: true, address: true } },
  currency: { select: { id: true, code: true, symbol: true } },
  salesOrder: { select: { id: true, number: true } },
  lines: { include: { product: { select: { id: true, sku: true, name: true, unit: true } } } },
  payments: {
    select: { id: true, number: true, amount: true, method: true, paidAt: true, reference: true },
  },
} satisfies Prisma.InvoiceInclude;

export interface InvoiceLineInput {
  productId?: string | null;
  description?: string;
  quantity: number;
  unitPrice: number;
  discount?: number;
  taxRate?: number;
}

export interface CreateInvoiceInput {
  salesOrderId?: string | null;
  customerId?: string | null;
  currencyId?: string | null;
  dueDate?: Date | null;
  notes?: string | null;
  lines?: InvoiceLineInput[];
  userId?: string;
}

/** Recomputes a customer's outstanding balance from their open invoices. */
export async function recalcCustomerBalance(tx: Tx, customerId: string): Promise<void> {
  const aggregate = await tx.invoice.aggregate({
    where: {
      customerId,
      status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
    },
    _sum: { balance: true },
  });
  await tx.customer.update({
    where: { id: customerId },
    data: { balance: round2(Number(aggregate._sum.balance ?? 0)) },
  });
}

interface BuiltInvoice {
  customerId: string | null;
  currencyId: string | null;
  exchangeRate: number;
  notes: string | null;
  dueDate: Date | null;
  lines: {
    productId: string | null;
    description: string;
    quantity: number;
    unitPrice: number;
    discount: number;
    taxRate: number;
    total: number;
  }[];
  totals: ReturnType<typeof documentTotals>;
}

async function buildFromSalesOrder(
  tx: Tx,
  salesOrderId: string,
  taxEnabled = true,
): Promise<BuiltInvoice> {
  const order = await tx.salesOrder.findUnique({
    where: { id: salesOrderId },
    include: { lines: { include: { product: true } } },
  });
  if (!order) throw ApiError.notFound('Sales order not found');
  if (order.status === 'DRAFT' || order.status === 'CANCELLED') {
    throw ApiError.badRequest('Only confirmed sales orders can be invoiced', 'NOT_INVOICEABLE');
  }

  const existing = await tx.invoice.findFirst({
    where: { salesOrderId, status: { not: 'VOID' } },
  });
  if (existing) {
    throw ApiError.conflict(`Sales order ${order.number} already has invoice ${existing.number}`, 'ALREADY_INVOICED');
  }

  const lines = order.lines.map((line) => {
    const taxRate = taxEnabled ? Number(line.taxRate) : 0;
    const total = lineTotals({
      quantity: line.quantity,
      unitPrice: Number(line.unitPrice),
      discount: Number(line.discount),
      taxRate,
    }).total;
    return {
      productId: line.productId,
      description: line.product?.name ?? 'Item',
      quantity: line.quantity,
      unitPrice: Number(line.unitPrice),
      discount: Number(line.discount),
      taxRate,
      total,
    };
  });

  return {
    customerId: order.customerId,
    currencyId: order.currencyId,
    exchangeRate: await exchangeRateFor(tx, order.currencyId),
    notes: order.notes,
    dueDate: null,
    lines,
    totals: documentTotals(
      lines.map((line) => ({
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        discount: line.discount,
        taxRate: line.taxRate,
      })),
    ),
  };
}

async function buildFromLines(input: CreateInvoiceInput, taxEnabled = true): Promise<BuiltInvoice> {
  const provided = input.lines ?? [];
  if (provided.length === 0) {
    throw ApiError.badRequest('An invoice needs either a salesOrderId or at least one line');
  }
  const lines = provided.map((line) => {
    const taxRate = taxEnabled ? line.taxRate ?? 0 : 0;
    const totals = lineTotals({
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discount: line.discount,
      taxRate,
    });
    return {
      productId: line.productId ?? null,
      description: line.description ?? 'Item',
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discount: line.discount ?? 0,
      taxRate,
      total: totals.total,
    };
  });
  return {
    customerId: input.customerId ?? null,
    currencyId: input.currencyId ?? null,
    exchangeRate: 1,
    notes: input.notes ?? null,
    dueDate: input.dueDate ?? null,
    lines,
    totals: documentTotals(
      lines.map((line) => ({
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        discount: line.discount,
        taxRate: line.taxRate,
      })),
    ),
  };
}

async function exchangeRateFor(tx: Tx, currencyId: string | null): Promise<number> {
  if (!currencyId) return 1;
  const currency = await tx.currency.findUnique({ where: { id: currencyId } });
  return currency ? Number(currency.exchangeRate) : 1;
}

export async function createInvoiceTx(tx: Tx, input: CreateInvoiceInput) {
  const taxEnabled = await isTaxEnabled();
  const built = input.salesOrderId
    ? await buildFromSalesOrder(tx, input.salesOrderId, taxEnabled)
    : await buildFromLines(input, taxEnabled);

  const exchangeRate = input.salesOrderId ? built.exchangeRate : await exchangeRateFor(tx, built.currencyId);
  const settings = await getSettings(tx);
  const number = await nextNumber(tx, 'invoice', settings.invoicePrefix);

  return tx.invoice.create({
    data: {
      number,
      customerId: built.customerId,
      salesOrderId: input.salesOrderId ?? null,
      currencyId: built.currencyId,
      status: 'DRAFT',
      dueDate: built.dueDate,
      notes: built.notes,
      exchangeRate,
      subtotal: built.totals.subtotal,
      discountTotal: built.totals.discountTotal,
      taxTotal: built.totals.taxTotal,
      total: built.totals.total,
      amountPaid: 0,
      balance: built.totals.total,
      lines: {
        create: built.lines.map((line) => ({
          productId: line.productId,
          description: line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          discount: line.discount,
          taxRate: line.taxRate,
          total: line.total,
        })),
      },
    },
    include: invoiceInclude,
  });
}

export async function issueInvoiceTx(tx: Tx, id: string, userId?: string) {
  const invoice = await tx.invoice.findUnique({ where: { id }, include: { lines: true } });
  if (!invoice) throw ApiError.notFound('Invoice not found');
  if (invoice.status !== 'DRAFT') {
    throw ApiError.badRequest(`Only draft invoices can be issued (current status: ${invoice.status})`, 'NOT_ISSUABLE');
  }

  const total = round2(Number(invoice.total));
  const subtotal = round2(Number(invoice.subtotal));
  const taxTotal = round2(Number(invoice.taxTotal));

  // Cost of goods sold from the products on the invoice.
  const productIds = invoice.lines.map((line) => line.productId).filter((v): v is string => Boolean(v));
  const products = productIds.length
    ? await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, costPrice: true } })
    : [];
  const costById = new Map(products.map((product) => [product.id, Number(product.costPrice)]));
  const cogs = round2(
    invoice.lines.reduce((sum, line) => {
      if (!line.productId) return sum;
      return sum + line.quantity * (costById.get(line.productId) ?? 0);
    }, 0),
  );

  const updated = await tx.invoice.update({
    where: { id },
    data: { status: 'ISSUED', issueDate: new Date() },
    include: invoiceInclude,
  });

  const journalLines: JournalLineInput[] = [
    { accountCode: ACCOUNT.RECEIVABLE, debit: total, description: `Invoice ${invoice.number}` },
    { accountCode: ACCOUNT.REVENUE, credit: subtotal, description: `Revenue ${invoice.number}` },
    { accountCode: ACCOUNT.TAX_PAYABLE, credit: taxTotal, description: `Tax on ${invoice.number}` },
  ];
  if (cogs > 0) {
    journalLines.push(
      { accountCode: ACCOUNT.COGS, debit: cogs, description: `Cost of sales ${invoice.number}` },
      { accountCode: ACCOUNT.INVENTORY, credit: cogs, description: `Inventory reduction ${invoice.number}` },
    );
  }

  await postJournal(tx, {
    memo: `Invoice ${invoice.number} issued`,
    reference: invoice.number,
    sourceType: 'INVOICE',
    sourceId: invoice.id,
    userId,
    lines: journalLines,
  });

  if (invoice.customerId) await recalcCustomerBalance(tx, invoice.customerId);

  return updated;
}

export async function voidInvoiceTx(tx: Tx, id: string, userId?: string) {
  const invoice = await tx.invoice.findUnique({ where: { id }, include: { payments: true } });
  if (!invoice) throw ApiError.notFound('Invoice not found');
  if (invoice.status === 'VOID') throw ApiError.badRequest('This invoice is already void');
  if (invoice.payments.length > 0) {
    throw ApiError.conflict('Cannot void an invoice that has payments recorded against it');
  }

  const wasIssued = invoice.status === 'ISSUED' || invoice.status === 'PARTIALLY_PAID' || invoice.status === 'PAID';
  const updated = await tx.invoice.update({
    where: { id },
    data: { status: 'VOID', balance: 0 },
    include: invoiceInclude,
  });

  if (wasIssued) {
    await postJournal(tx, {
      memo: `Invoice ${invoice.number} voided`,
      reference: invoice.number,
      sourceType: 'INVOICE_VOID',
      sourceId: invoice.id,
      userId,
      lines: [
        { accountCode: ACCOUNT.REVENUE, debit: round2(Number(invoice.subtotal)), description: `Reverse revenue ${invoice.number}` },
        { accountCode: ACCOUNT.TAX_PAYABLE, debit: round2(Number(invoice.taxTotal)), description: `Reverse tax ${invoice.number}` },
        { accountCode: ACCOUNT.RECEIVABLE, credit: round2(Number(invoice.total)), description: `Reverse receivable ${invoice.number}` },
      ],
    });
  }

  if (invoice.customerId) await recalcCustomerBalance(tx, invoice.customerId);

  return updated;
}

// ---------------------------------------------------------------------------
// Route-facing wrappers
// ---------------------------------------------------------------------------

export async function createInvoice(input: CreateInvoiceInput) {
  return prisma.$transaction((tx) => createInvoiceTx(tx, input));
}

export async function issueInvoice(id: string, userId?: string) {
  return prisma.$transaction((tx) => issueInvoiceTx(tx, id, userId));
}

export async function voidInvoice(id: string, userId?: string) {
  return prisma.$transaction((tx) => voidInvoiceTx(tx, id, userId));
}

export interface UpdateInvoiceInput {
  customerId?: string | null;
  currencyId?: string | null;
  dueDate?: Date | null;
  notes?: string | null;
  lines?: InvoiceLineInput[];
}

export async function updateInvoiceTx(tx: Tx, id: string, input: UpdateInvoiceInput) {
  const invoice = await tx.invoice.findUnique({ where: { id } });
  if (!invoice) throw ApiError.notFound('Invoice not found');
  if (invoice.status !== 'DRAFT') {
    throw ApiError.badRequest('Only draft invoices can be updated', 'NOT_EDITABLE');
  }

  const built = input.lines && input.lines.length > 0
    ? await buildFromLines(
        {
          ...input,
          lines: input.lines,
        },
        await isTaxEnabled(),
      )
    : {
        customerId: input.customerId ?? invoice.customerId,
        currencyId: input.currencyId ?? invoice.currencyId,
        exchangeRate: await exchangeRateFor(tx, input.currencyId ?? invoice.currencyId),
        notes: input.notes ?? invoice.notes,
        dueDate: input.dueDate ?? invoice.dueDate,
        lines: [],
        totals: {
          subtotal: Number(invoice.subtotal),
          discountTotal: Number(invoice.discountTotal),
          taxTotal: Number(invoice.taxTotal),
          total: Number(invoice.total),
        },
      };

  const exchangeRate = built.lines.length > 0
    ? await exchangeRateFor(tx, built.currencyId)
    : built.exchangeRate;

  const data: Prisma.InvoiceUpdateInput = {};
  if (input.customerId !== undefined) {
    data.customer = input.customerId ? { connect: { id: input.customerId } } : { disconnect: true };
  }
  if (input.currencyId !== undefined) {
    data.currency = input.currencyId ? { connect: { id: input.currencyId } } : { disconnect: true };
  }
  if (input.notes !== undefined) data.notes = input.notes;
  if (input.dueDate !== undefined) data.dueDate = input.dueDate;
  data.exchangeRate = exchangeRate;

  if (built.lines.length > 0) {
    await tx.invoiceLine.deleteMany({ where: { invoiceId: id } });
    data.subtotal = built.totals.subtotal;
    data.discountTotal = built.totals.discountTotal;
    data.taxTotal = built.totals.taxTotal;
    data.total = built.totals.total;
    data.balance = built.totals.total;
    data.lines = {
      create: built.lines.map((line) => ({
        productId: line.productId,
        description: line.description,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        discount: line.discount,
        taxRate: line.taxRate,
        total: line.total,
      })),
    };
  }

  const updated = await tx.invoice.update({ where: { id }, data, include: invoiceInclude });
  if (updated.customerId) await recalcCustomerBalance(tx, updated.customerId);
  return updated;
}

export async function updateInvoice(id: string, input: UpdateInvoiceInput) {
  return prisma.$transaction((tx) => updateInvoiceTx(tx, id, input));
}
