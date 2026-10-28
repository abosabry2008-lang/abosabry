import { PaymentMethod, Prisma, SalesChannel } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { documentTotals, round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { getSettings, isTaxEnabled } from '../../lib/settings';
import { applyMovement, resolveLocation } from '../inventory/inventory.service';
import { drawFromWarehouse } from '../inventory/inventory.service';
import { ACCOUNT, postJournal, reverseJournalBySource } from '../accounting/accounting.service';

export const salesOrderInclude = {
  customer: { select: { id: true, name: true, email: true, phone: true } },
  warehouse: { select: { id: true, code: true, name: true } },
  currency: { select: { id: true, code: true, symbol: true } },
  user: { select: { id: true, name: true } },
  paymentCashBox: { select: { id: true, code: true, name: true } },
  lines: {
    include: {
      product: {
        select: {
          id: true,
          sku: true,
          name: true,
          unit: true,
          boxesPerCarton: true,
          boxPrice: true,
          cartonPrice: true,
          salePrice: true,
          costPrice: true,
        },
      },
    },
  },
} satisfies Prisma.SalesOrderInclude;

export interface SalesLineInput {
  productId: string;
  quantity: number;
  unitPrice?: number;
  discount?: number;
  taxRate?: number;
  sellUnit?: 'unit' | 'box' | 'carton';
}

interface ResolvedLine {
  productId: string;
  quantity: number;
  unitPrice: number;
  /// Cost snapshot so later purchase-price changes do not rewrite profit.
  unitCost: number;
  discount: number;
  taxRate: number;
  sellUnit: string;
}

function resolvePack(
  product: { boxesPerCarton: number; boxPrice: unknown; cartonPrice: unknown; salePrice: unknown },
  sellUnit: string,
) {
  const boxesPerCarton = product.boxesPerCarton ?? 0;
  if (sellUnit === 'box' && boxesPerCarton > 0) {
    const boxPrice = product.boxPrice != null ? Number(product.boxPrice) : Number(product.salePrice);
    return { baseQty: boxesPerCarton > 0 ? 1 : 1, qtyInBase: 1, unitPrice: boxPrice, sellUnit: 'box' };
  }
  if (sellUnit === 'carton' && boxesPerCarton > 0) {
    const cartonPrice =
      product.cartonPrice != null ? Number(product.cartonPrice) : boxesPerCarton * Number(product.salePrice);
    // Stock and invoice quantities are stored in boxes (the base unit), so the
    // carton price is split across its boxes.
    return {
      baseQty: boxesPerCarton,
      qtyInBase: boxesPerCarton,
      unitPrice: cartonPrice / boxesPerCarton,
      sellUnit: 'carton',
    };
  }
  return { baseQty: 1, qtyInBase: 1, unitPrice: Number(product.salePrice), sellUnit: 'unit' };
}

async function resolveLines(
  tx: Tx,
  lines: SalesLineInput[],
  taxEnabled = true,
): Promise<ResolvedLine[]> {
  if (!lines || lines.length === 0) throw ApiError.badRequest('An order needs at least one line');

  const products = await tx.product.findMany({
    where: { id: { in: lines.map((line) => line.productId) } },
  });
  const byId = new Map(products.map((product) => [product.id, product]));

  return lines.map((line) => {
    const product = byId.get(line.productId);
    if (!product) throw ApiError.badRequest(`Product ${line.productId} not found`, 'PRODUCT_NOT_FOUND');
    const sellUnit = line.sellUnit === 'box' || line.sellUnit === 'carton' ? line.sellUnit : 'unit';
    const pack = resolvePack(product, sellUnit);
    // A carton price is split across its boxes; stock and line quantities are
    // stored in boxes, so the stored unit price must be per box. `pack.unitPrice`
    // is already per box, while an operator-entered carton price is per carton.
    const unitPrice =
      sellUnit === 'carton' && (product.boxesPerCarton ?? 0) > 0
        ? line.unitPrice != null
          ? line.unitPrice / Number(product.boxesPerCarton)
          : pack.unitPrice
        : line.unitPrice ?? pack.unitPrice;
    // لا يُسمح بالبيع بسعر أقل من التكلفة.
    const costPrice = Number(product.costPrice);
    if (unitPrice < costPrice) {
      throw ApiError.badRequest(
        `Selling price for "${product.name}" (${unitPrice}) is below its cost price (${costPrice})`,
        'BELOW_COST',
        { productId: product.id, unitPrice, costPrice },
      );
    }
    const quantity = sellUnit === 'carton' && (product.boxesPerCarton ?? 0) > 0 ? line.quantity * (product.boxesPerCarton ?? 1) : sellUnit === 'box' ? line.quantity : line.quantity;
    // quantity stored in base units for inventory
    const baseQuantity = sellUnit === 'carton' && (product.boxesPerCarton ?? 0) > 0 ? line.quantity * (product.boxesPerCarton ?? 1) : line.quantity;
    return {
      productId: line.productId,
      quantity: baseQuantity,
      unitPrice,
      unitCost: costPrice,
      discount: line.discount ?? 0,
      taxRate: taxEnabled ? line.taxRate ?? Number(product.taxRate) : 0,
      sellUnit,
    };
  });
}

function totalsOf(lines: ResolvedLine[]) {
  return documentTotals(
    lines.map((line) => ({
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discount: line.discount,
      taxRate: line.taxRate,
    })),
  );
}

export interface CreateSalesOrderInput {
  customerId?: string | null;
  warehouseId: string;
  currencyId?: string | null;
  channel?: SalesChannel;
  orderDate?: Date;
  notes?: string | null;
  userId?: string;
  paidAmount?: number;
  paymentCashBoxId?: string | null;
  paymentMethod?: PaymentMethod;
  lines: SalesLineInput[];
}

export async function createSalesOrderTx(tx: Tx, input: CreateSalesOrderInput) {
  const settings = await getSettings(tx);
  const lines = await resolveLines(tx, input.lines, settings.taxEnabled);
  const totals = totalsOf(lines);
  const paidAmount = round2(Number(input.paidAmount ?? 0));
  if (paidAmount < 0 || paidAmount > round2(totals.total)) {
    throw ApiError.badRequest(
      'The paid amount must be between zero and the order total',
      'INVALID_PAID_AMOUNT',
    );
  }
  const now = new Date();
  const orderDate = input.orderDate ?? now;
  const number = await nextNumber(
    tx,
    'salesOrder',
    settings.salesOrderPrefix,
    orderDate,
    async (candidate) => (await tx.salesOrder.count({ where: { number: candidate } })) > 0,
  );

  return tx.salesOrder.create({
    data: {
      number,
      customerId: input.customerId ?? null,
      warehouseId: input.warehouseId,
      currencyId: input.currencyId ?? null,
      channel: input.channel ?? 'MANUAL',
      status: 'DRAFT',
      orderDate,
      notes: input.notes ?? null,
      userId: input.userId ?? null,
      subtotal: totals.subtotal,
      discountTotal: totals.discountTotal,
      taxTotal: totals.taxTotal,
      total: totals.total,
      paidAmount,
      paymentCashBoxId: input.paymentCashBoxId ?? null,
      paymentMethod: input.paymentMethod ?? 'CASH',
      lines: {
        create: lines.map((line) => ({
          productId: line.productId,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          unitCost: line.unitCost,
          discount: line.discount,
          taxRate: line.taxRate,
          sellUnit: line.sellUnit,
        })),
      },
    },
    include: salesOrderInclude,
  });
}

export async function confirmSalesOrderTx(tx: Tx, id: string) {
  const order = await tx.salesOrder.findUnique({ where: { id } });
  if (!order) throw ApiError.notFound('Sales order not found');
  if (order.status !== 'DRAFT') {
    throw ApiError.badRequest(`A ${order.status.toLowerCase()} order cannot be confirmed`, 'NOT_CONFIRMABLE');
  }
  return tx.salesOrder.update({ where: { id }, data: { status: 'CONFIRMED' }, include: salesOrderInclude });
}

export interface FulfillInput {
  lines?: { lineId: string; quantity: number }[];
  userId?: string;
  /**
   * When true, lines are fulfilled only up to what is physically on hand
   * instead of failing with `INSUFFICIENT_STOCK`. Used after the operator is
   * warned that some items are missing (نواقص).
   */
  onlyAvailable?: boolean;
}

/** Available stock of a product across the active locations of a warehouse. */
async function availableInWarehouse(
  tx: Tx,
  warehouseId: string,
  productId: string,
): Promise<number> {
  const locations = await tx.location.findMany({
    where: { warehouseId, active: true },
    select: { id: true },
  });
  if (locations.length === 0) return 0;
  const levels = await tx.stockLevel.findMany({
    where: {
      productId,
      locationId: { in: locations.map((location) => location.id) },
      quantity: { gt: 0 },
    },
    select: { quantity: true },
  });
  return levels.reduce((sum, level) => sum + level.quantity, 0);
}

export interface LineAvailability {
  lineId: string;
  productId: string;
  productName: string;
  sku: string | null;
  /** Quantity still to be delivered on this line. */
  requested: number;
  /** Quantity on hand in the order's warehouse. */
  available: number;
  /** How much of the request cannot be met. */
  shortfall: number;
}

export interface OrderAvailability {
  orderId: string;
  orderNumber: string;
  warehouseId: string;
  canFulfillEverything: boolean;
  lines: LineAvailability[];
  totals: { requested: number; available: number; shortfall: number };
}

/**
 * Compares every open line of an order with the stock on hand, so the UI can
 * warn before fulfilling that some items are missing.
 */
export async function checkSalesOrderAvailability(id: string): Promise<OrderAvailability> {
  return prisma.$transaction(async (tx) => {
    const order = await tx.salesOrder.findUnique({
      where: { id },
      include: {
        lines: {
          include: {
            product: { select: { id: true, name: true, sku: true } },
          },
        },
      },
    });
    if (!order) throw ApiError.notFound('Sales order not found');

    const lines: LineAvailability[] = [];
    for (const line of order.lines) {
      const requested = line.quantity - line.fulfilledQty;
      if (requested <= 0) continue;
      const available = await availableInWarehouse(tx, order.warehouseId, line.productId);
      lines.push({
        lineId: line.id,
        productId: line.productId,
        productName: line.product.name,
        sku: line.product.sku,
        requested,
        available,
        shortfall: Math.max(0, requested - available),
      });
    }

    const totals = lines.reduce(
      (acc, line) => ({
        requested: acc.requested + line.requested,
        available: acc.available + line.available,
        shortfall: acc.shortfall + line.shortfall,
      }),
      { requested: 0, available: 0, shortfall: 0 },
    );

    return {
      orderId: order.id,
      orderNumber: order.number,
      warehouseId: order.warehouseId,
      canFulfillEverything: totals.shortfall === 0,
      lines,
      totals,
    };
  });
}

export async function fulfillSalesOrderTx(tx: Tx, id: string, input: FulfillInput) {
  const order = await tx.salesOrder.findUnique({
    where: { id },
    include: {
      lines: {
        include: {
          product: { select: { name: true, costPrice: true } },
        },
      },
    },
  });
  if (!order) throw ApiError.notFound('Sales order not found');
  if (order.status === 'CANCELLED') throw ApiError.badRequest('A cancelled order cannot be fulfilled');
  if (order.status === 'FULFILLED') throw ApiError.badRequest('This order has already been fulfilled');

  for (const line of order.lines) {
    const requested = input.lines
      ? input.lines.find((entry) => entry.lineId === line.id)?.quantity ?? 0
      : line.quantity - line.fulfilledQty;

    const remaining = line.quantity - line.fulfilledQty;
    let quantity = Math.min(Math.max(0, requested), remaining);
    if (quantity <= 0) continue;

    // When the operator chose to skip missing items, cap the draw at what is
    // actually on the shelf instead of failing the whole fulfilment.
    if (input.onlyAvailable) {
      const available = await availableInWarehouse(tx, order.warehouseId, line.productId);
      quantity = Math.min(quantity, available);
      if (quantity <= 0) continue;
    }

    await drawFromWarehouse(tx, {
      warehouseId: order.warehouseId,
      productId: line.productId,
      quantity,
      type: 'SALE',
      // The cost snapshot on the line; fall back to the product cost for older
      // orders written before costs were stored.
      unitCost: Number(
        Number(line.unitCost) || Number(line.product.costPrice),
      ),
      reference: order.number,
      userId: input.userId,
    });

    await tx.salesOrderLine.update({
      where: { id: line.id },
      data: { fulfilledQty: { increment: quantity } },
    });
  }

  const refreshed = await tx.salesOrderLine.findMany({ where: { salesOrderId: id } });
  const fullyFulfilled = refreshed.length > 0 && refreshed.every((line) => line.fulfilledQty >= line.quantity);
  const partiallyFulfilled = refreshed.some((line) => line.fulfilledQty > 0);

  return tx.salesOrder.update({
    where: { id },
    data: {
      status: fullyFulfilled ? 'FULFILLED' : partiallyFulfilled ? 'PARTIALLY_FULFILLED' : order.status,
      fulfilledAt: fullyFulfilled ? new Date() : null,
    },
    include: salesOrderInclude,
  });
}

/**
 * Puts every fulfilled quantity of an order back on the shelf.
 *
 * Used when a fulfilled order is cancelled or re-edited: stock that left the
 * warehouse for this order is returned to the warehouse's default location so
 * balances match the document again.
 */
interface FulfilledLine {
  id: string;
  productId: string;
  fulfilledQty: number;
  /** Cost snapshot captured when the line left the warehouse. */
  unitCost?: unknown;
}

async function restoreFulfilledStock(
  tx: Tx,
  order: { number: string; warehouseId: string },
  lines: FulfilledLine[],
  userId?: string,
) {
  const pending = lines.filter((line) => line.fulfilledQty > 0);
  if (pending.length === 0) return;

  const location = await resolveLocation(tx, order.warehouseId);

  for (const line of pending) {
    // Reverse at the same cost the goods left with. Using the selling price
    // here would inflate the inventory value every time an order is edited or
    // cancelled.
    let cost = Number(line.unitCost);
    if (!(cost > 0)) {
      const product = await tx.product.findUnique({
        where: { id: line.productId },
        select: { costPrice: true },
      });
      cost = Number(product?.costPrice ?? 0);
    }
    await applyMovement(tx, {
      type: 'SALE_RETURN',
      productId: line.productId,
      locationId: location.id,
      quantity: line.fulfilledQty,
      unitCost: cost,
      reference: order.number,
      note: `Reversed fulfilment of ${order.number}`,
      userId,
    });
    await tx.salesOrderLine.update({
      where: { id: line.id },
      data: { fulfilledQty: 0 },
    });
  }
}

/** Creates, confirms and fulfils an order in one step (used by the POS). */
export async function registerSaleTx(
  tx: Tx,
  input: CreateSalesOrderInput,
  userId?: string,
) {
  const order = await createSalesOrderTx(tx, { ...input, userId });
  await confirmSalesOrderTx(tx, order.id);
  return fulfillSalesOrderTx(tx, order.id, { userId });
}

// ---------------------------------------------------------------------------
// Transaction-wrapping entry points used by the routes
// ---------------------------------------------------------------------------

export async function createSalesOrder(input: CreateSalesOrderInput) {
  return prisma.$transaction((tx) => createSalesOrderTx(tx, input));
}

export interface UpdateSalesOrderOptions {
  /**
   * Admins may edit an order that has already left the draft state. Any
   * fulfilled quantity is returned to stock and re-applied from the new lines,
   * so inventory stays consistent with the document.
   */
  allowPosted?: boolean;
  /** Internal flag: the line change originates from the linked invoice. */
  fromInvoiceSync?: boolean;
  userId?: string;
}

export async function updateSalesOrder(
  id: string,
  input: {
    customerId?: string | null;
    currencyId?: string | null;
    orderDate?: Date;
    notes?: string | null;
    paidAmount?: number;
    paymentCashBoxId?: string | null;
    paymentMethod?: PaymentMethod;
    lines?: SalesLineInput[];
  },
  options: UpdateSalesOrderOptions = {},
) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.salesOrder.findUnique({
      where: { id },
      include: { lines: true },
    });
    if (!existing) throw ApiError.notFound('Sales order not found');
    if (existing.status === 'CANCELLED') {
      throw ApiError.badRequest('A cancelled sales order cannot be edited', 'NOT_EDITABLE');
    }

    const editable =
      existing.status === 'DRAFT' || options.allowPosted === true;
    if (!editable) {
      throw ApiError.badRequest('Only draft sales orders can be edited', 'NOT_EDITABLE');
    }

    // Once the order has an issued invoice, its lines are owned by that
    // invoice (which also keeps stock in sync). Editing them here would make
    // the invoice, stock and order drift apart.
    if (input.lines && options.fromInvoiceSync !== true) {
      const invoiced = await tx.invoice.count({
        where: {
          salesOrderId: id,
          status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
        },
      });
      if (invoiced > 0) {
        throw ApiError.badRequest(
          'This sales order is already invoiced — edit the invoice lines instead',
          'ORDER_ALREADY_INVOICED',
        );
      }
    }

    // Once the order is invoiced the payment has already been posted, so the
    // paid amount can only be changed from the invoice (as a new payment).
    if (
      input.paidAmount !== undefined &&
      round2(Number(input.paidAmount)) !== round2(Number(existing.paidAmount))
    ) {
      const invoiced = await tx.invoice.findFirst({
        where: {
          salesOrderId: id,
          status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
        },
        select: { number: true },
      });
      if (invoiced) {
        throw ApiError.badRequest(
          `Order ${existing.number} is already invoiced (${invoiced.number}); record further payments from the invoice`,
          'ORDER_ALREADY_INVOICED',
        );
      }
    }

    // Editing a fulfilled order changes what should have left the warehouse,
    // so the old fulfilment is rolled back before the new lines are applied.
    const hadFulfilment = existing.lines.some((line) => line.fulfilledQty > 0);
    if (hadFulfilment) {
      if (existing.status === 'FULFILLED' || existing.status === 'PARTIALLY_FULFILLED') {
        await restoreFulfilledStock(
          tx,
          existing,
          existing.lines.map((line) => ({
            id: line.id,
            productId: line.productId,
            fulfilledQty: line.fulfilledQty,
            unitCost: line.unitCost,
          })),
          options.userId,
        );
      }
    }

    const data: Prisma.SalesOrderUpdateInput = {};
    if (input.customerId !== undefined) {
      data.customer = input.customerId ? { connect: { id: input.customerId } } : { disconnect: true };
    }
    if (input.currencyId !== undefined) {
      data.currency = input.currencyId ? { connect: { id: input.currencyId } } : { disconnect: true };
    }
    if (input.notes !== undefined) data.notes = input.notes;
    if (input.orderDate !== undefined) data.orderDate = input.orderDate;
    if (input.paidAmount !== undefined) {
      const paid = round2(Number(input.paidAmount));
      if (paid < 0) {
        throw ApiError.badRequest('The paid amount cannot be negative', 'INVALID_PAID_AMOUNT');
      }
      data.paidAmount = paid;
    }
    if (input.paymentCashBoxId !== undefined) {
      data.paymentCashBox = input.paymentCashBoxId
        ? { connect: { id: input.paymentCashBoxId } }
        : { disconnect: true };
    }
    if (input.paymentMethod !== undefined) {
      data.paymentMethod = input.paymentMethod;
    }

    if (input.lines) {
      const settings = await getSettings(tx);
      const lines = await resolveLines(tx, input.lines, settings.taxEnabled);
      const totals = totalsOf(lines);
      await tx.salesOrderLine.deleteMany({ where: { salesOrderId: id } });
      data.subtotal = totals.subtotal;
      data.discountTotal = totals.discountTotal;
      data.taxTotal = totals.taxTotal;
      data.total = totals.total;
      data.lines = {
        create: lines.map((line) => ({
          productId: line.productId,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          unitCost: line.unitCost,
          discount: line.discount,
          taxRate: line.taxRate,
          sellUnit: line.sellUnit,
        })),
      };
      // Changing the lines of a fulfilment resets it: the order goes back to
      // CONFIRMED and the stock is re-drawn from the new quantities below.
      if (existing.status === 'FULFILLED' || existing.status === 'PARTIALLY_FULFILLED') {
        data.status = 'CONFIRMED';
        data.fulfilledAt = null;
      }
    }

    const effectiveTotal = input.lines
      ? Number(data.total ?? 0)
      : Number(existing.total);
    if (
      data.paidAmount !== undefined &&
      Number(data.paidAmount) > round2(effectiveTotal)
    ) {
      throw ApiError.badRequest(
        'The paid amount cannot exceed the order total',
        'INVALID_PAID_AMOUNT',
      );
    }

    const updated = await tx.salesOrder.update({ where: { id }, data, include: salesOrderInclude });

    // Re-draw the stock for an order that was fulfilled before the edit.
    if (hadFulfilment && input.lines && updated.status === 'CONFIRMED') {
      return fulfillSalesOrderTx(tx, id, { userId: options.userId });
    }

    return updated;
  });
}

export async function confirmSalesOrder(id: string) {
  return prisma.$transaction((tx) => confirmSalesOrderTx(tx, id));
}

export async function fulfillSalesOrder(id: string, input: FulfillInput) {
  return prisma.$transaction((tx) => fulfillSalesOrderTx(tx, id, input));
}

export interface CancelSalesOrderOptions {
  userId?: string;
}

/**
 * Cancels a sales order — including one that was already fulfilled.
 *
 * Cancelling an executed order reverses everything it caused: the stock that
 * left the warehouse comes back, and any ledger entry posted for the order is
 * reversed, so inventory and accounting no longer reflect a document we are
 * pulling back.
 */
export async function cancelSalesOrder(id: string, options: CancelSalesOrderOptions = {}) {
  return prisma.$transaction(async (tx) => {
    const order = await tx.salesOrder.findUnique({
      where: { id },
      include: { lines: true, invoices: { select: { id: true, number: true, status: true } } },
    });
    if (!order) throw ApiError.notFound('Sales order not found');
    if (order.status === 'CANCELLED') {
      throw ApiError.badRequest('This order is already cancelled');
    }

    // Live invoices must be voided first, otherwise revenue would stay on the
    // books for an order that no longer exists.
    const liveInvoices = order.invoices.filter((invoice) => invoice.status !== 'VOID');
    if (liveInvoices.length > 0) {
      throw ApiError.conflict(
        `This order has an active invoice (${liveInvoices.map((i) => i.number).join(', ')}) — void it first`,
        'HAS_INVOICES',
        { invoices: liveInvoices.map((invoice) => invoice.number) },
      );
    }

    // Put back whatever was fulfilled.
    await restoreFulfilledStock(
      tx,
      order,
      order.lines.map((line) => ({
        id: line.id,
        productId: line.productId,
        fulfilledQty: line.fulfilledQty,
        unitCost: line.unitCost,
      })),
      options.userId,
    );

    // Reverse any ledger entry posted for the order itself.
    await reverseJournalBySource(tx, {
      sourceType: 'SALES_ORDER',
      sourceId: order.id,
      reversalSourceType: 'SALES_ORDER_CANCEL',
      memo: `Sales order ${order.number} cancelled`,
      reference: order.number,
      userId: options.userId,
    });

    return tx.salesOrder.update({
      where: { id },
      data: { status: 'CANCELLED', fulfilledAt: null },
      include: salesOrderInclude,
    });
  });
}
