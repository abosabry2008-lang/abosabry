import { Prisma, SalesChannel } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { documentTotals } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { getSettings, isTaxEnabled } from '../../lib/settings';
import { drawFromWarehouse } from '../inventory/inventory.service';

export const salesOrderInclude = {
  customer: { select: { id: true, name: true, email: true, phone: true } },
  warehouse: { select: { id: true, code: true, name: true } },
  currency: { select: { id: true, code: true, symbol: true } },
  user: { select: { id: true, name: true } },
  lines: { include: { product: { select: { id: true, sku: true, name: true, unit: true } } } },
} satisfies Prisma.SalesOrderInclude;

export interface SalesLineInput {
  productId: string;
  quantity: number;
  unitPrice?: number;
  discount?: number;
  taxRate?: number;
}

interface ResolvedLine {
  productId: string;
  quantity: number;
  unitPrice: number;
  discount: number;
  taxRate: number;
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
    return {
      productId: line.productId,
      quantity: line.quantity,
      unitPrice: line.unitPrice ?? Number(product.salePrice),
      discount: line.discount ?? 0,
      taxRate: taxEnabled ? line.taxRate ?? Number(product.taxRate) : 0,
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
  notes?: string | null;
  userId?: string;
  lines: SalesLineInput[];
}

export async function createSalesOrderTx(tx: Tx, input: CreateSalesOrderInput) {
  const settings = await getSettings(tx);
  const lines = await resolveLines(tx, input.lines, settings.taxEnabled);
  const totals = totalsOf(lines);
  const now = new Date();
  const number = await nextNumber(tx, 'salesOrder', settings.salesOrderPrefix, now);

  return tx.salesOrder.create({
    data: {
      number,
      customerId: input.customerId ?? null,
      warehouseId: input.warehouseId,
      currencyId: input.currencyId ?? null,
      channel: input.channel ?? 'MANUAL',
      status: 'DRAFT',
      notes: input.notes ?? null,
      userId: input.userId ?? null,
      subtotal: totals.subtotal,
      discountTotal: totals.discountTotal,
      taxTotal: totals.taxTotal,
      total: totals.total,
      lines: {
        create: lines.map((line) => ({
          productId: line.productId,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          discount: line.discount,
          taxRate: line.taxRate,
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
}

export async function fulfillSalesOrderTx(tx: Tx, id: string, input: FulfillInput) {
  const order = await tx.salesOrder.findUnique({ where: { id }, include: { lines: true } });
  if (!order) throw ApiError.notFound('Sales order not found');
  if (order.status === 'CANCELLED') throw ApiError.badRequest('A cancelled order cannot be fulfilled');
  if (order.status === 'FULFILLED') throw ApiError.badRequest('This order has already been fulfilled');

  for (const line of order.lines) {
    const requested = input.lines
      ? input.lines.find((entry) => entry.lineId === line.id)?.quantity ?? 0
      : line.quantity - line.fulfilledQty;

    const remaining = line.quantity - line.fulfilledQty;
    const quantity = Math.min(Math.max(0, requested), remaining);
    if (quantity <= 0) continue;

    await drawFromWarehouse(tx, {
      warehouseId: order.warehouseId,
      productId: line.productId,
      quantity,
      type: 'SALE',
      unitCost: Number(line.unitPrice),
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

export async function updateSalesOrder(
  id: string,
  input: { customerId?: string | null; currencyId?: string | null; notes?: string | null; lines?: SalesLineInput[] },
) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.salesOrder.findUnique({ where: { id } });
    if (!existing) throw ApiError.notFound('Sales order not found');
    if (existing.status !== 'DRAFT') {
      throw ApiError.badRequest('Only draft sales orders can be edited', 'NOT_EDITABLE');
    }

    const data: Prisma.SalesOrderUpdateInput = {};
    if (input.customerId !== undefined) {
      data.customer = input.customerId ? { connect: { id: input.customerId } } : { disconnect: true };
    }
    if (input.currencyId !== undefined) {
      data.currency = input.currencyId ? { connect: { id: input.currencyId } } : { disconnect: true };
    }
    if (input.notes !== undefined) data.notes = input.notes;

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
          discount: line.discount,
          taxRate: line.taxRate,
        })),
      };
    }

    return tx.salesOrder.update({ where: { id }, data, include: salesOrderInclude });
  });
}

export async function confirmSalesOrder(id: string) {
  return prisma.$transaction((tx) => confirmSalesOrderTx(tx, id));
}

export async function fulfillSalesOrder(id: string, input: FulfillInput) {
  return prisma.$transaction((tx) => fulfillSalesOrderTx(tx, id, input));
}

export async function cancelSalesOrder(id: string) {
  return prisma.$transaction(async (tx) => {
    const order = await tx.salesOrder.findUnique({ where: { id } });
    if (!order) throw ApiError.notFound('Sales order not found');
    if (order.status === 'FULFILLED' || order.status === 'PARTIALLY_FULFILLED') {
      throw ApiError.badRequest('A fulfilled order cannot be cancelled', 'NOT_CANCELLABLE');
    }
    if (order.status === 'CANCELLED') {
      throw ApiError.badRequest('This order is already cancelled');
    }
    return tx.salesOrder.update({ where: { id }, data: { status: 'CANCELLED' }, include: salesOrderInclude });
  });
}
