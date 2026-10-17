import { MovementType } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { prisma, type Tx } from '../../lib/prisma';

export interface MovementInput {
  type: MovementType;
  productId: string;
  locationId: string;
  /** Signed delta: positive adds stock, negative removes it. */
  quantity: number;
  unitCost?: number;
  reference?: string;
  note?: string;
  userId?: string;
}

/**
 * Applies a stock delta to a location and records the audit movement.
 * Must be called inside a transaction.
 */
export async function applyMovement(tx: Tx, input: MovementInput): Promise<number> {
  if (input.quantity === 0) {
    throw ApiError.badRequest('Movement quantity must not be zero', 'ZERO_MOVEMENT');
  }

  const location = await tx.location.findUnique({ where: { id: input.locationId } });
  if (!location) throw ApiError.badRequest('Location not found', 'LOCATION_NOT_FOUND');

  const product = await tx.product.findUnique({ where: { id: input.productId } });
  if (!product) throw ApiError.badRequest('Product not found', 'PRODUCT_NOT_FOUND');

  const level = await tx.stockLevel.upsert({
    where: {
      productId_locationId: { productId: input.productId, locationId: input.locationId },
    },
    create: {
      productId: input.productId,
      locationId: input.locationId,
      warehouseId: location.warehouseId,
      quantity: input.quantity,
    },
    update: { quantity: { increment: input.quantity } },
  });

  await tx.stockMovement.create({
    data: {
      type: input.type,
      productId: input.productId,
      locationId: input.locationId,
      warehouseId: location.warehouseId,
      quantity: input.quantity,
      unitCost: input.unitCost ?? 0,
      balanceAfter: level.quantity,
      reference: input.reference,
      note: input.note,
      userId: input.userId,
    },
  });

  return level.quantity;
}

export async function stockAt(locationId: string, productId: string): Promise<number> {
  const level = await prisma.stockLevel.findUnique({
    where: { productId_locationId: { productId, locationId } },
  });
  return level?.quantity ?? 0;
}

/** Total stock per product across all locations. */
export async function totalStockByProduct(productIds: string[]): Promise<Map<string, number>> {
  if (productIds.length === 0) return new Map();
  const rows = await prisma.stockLevel.groupBy({
    by: ['productId'],
    where: { productId: { in: productIds } },
    _sum: { quantity: true },
  });
  return new Map(rows.map((row) => [row.productId, row._sum.quantity ?? 0]));
}

export interface ReceiveStockInput {
  productId: string;
  locationId: string;
  quantity: number;
  unitCost?: number;
  reference?: string;
  note?: string;
  userId?: string;
}

export async function receiveStock(input: ReceiveStockInput): Promise<{ balance: number }> {
  if (input.quantity <= 0) throw ApiError.badRequest('Quantity must be greater than zero');
  const balance = await prisma.$transaction((tx) =>
    applyMovement(tx, {
      type: 'RECEIVE',
      productId: input.productId,
      locationId: input.locationId,
      quantity: Math.abs(input.quantity),
      unitCost: input.unitCost,
      reference: input.reference,
      note: input.note,
      userId: input.userId,
    }),
  );
  return { balance };
}

export interface DispatchStockInput extends ReceiveStockInput {
  allowNegative?: boolean;
}

export async function dispatchStock(input: DispatchStockInput): Promise<{ balance: number }> {
  if (input.quantity <= 0) throw ApiError.badRequest('Quantity must be greater than zero');
  const quantity = Math.abs(input.quantity);
  const balance = await prisma.$transaction(async (tx) => {
    const current = await tx.stockLevel.findUnique({
      where: { productId_locationId: { productId: input.productId, locationId: input.locationId } },
    });
    const available = current?.quantity ?? 0;
    if (!input.allowNegative && available < quantity) {
      throw ApiError.badRequest(
        `Insufficient stock: ${available} available, ${quantity} requested`,
        'INSUFFICIENT_STOCK',
        { available, requested: quantity },
      );
    }
    return applyMovement(tx, {
      type: 'DISPATCH',
      productId: input.productId,
      locationId: input.locationId,
      quantity: -quantity,
      unitCost: input.unitCost,
      reference: input.reference,
      note: input.note,
      userId: input.userId,
    });
  });
  return { balance };
}

export interface AdjustStockInput {
  productId: string;
  locationId: string;
  /** The signed correction to apply (can be negative). */
  quantity: number;
  reason?: string;
  userId?: string;
}

export async function adjustStock(input: AdjustStockInput): Promise<{ balance: number }> {
  if (input.quantity === 0) throw ApiError.badRequest('Adjustment quantity must not be zero');
  const balance = await prisma.$transaction((tx) =>
    applyMovement(tx, {
      type: 'ADJUSTMENT',
      productId: input.productId,
      locationId: input.locationId,
      quantity: input.quantity,
      note: input.reason,
      userId: input.userId,
    }),
  );
  return { balance };
}

export interface TransferStockInput {
  productId: string;
  fromLocationId: string;
  toLocationId: string;
  quantity: number;
  note?: string;
  userId?: string;
}

export async function transferStock(input: TransferStockInput): Promise<{ fromBalance: number; toBalance: number }> {
  if (input.quantity <= 0) throw ApiError.badRequest('Quantity must be greater than zero');
  if (input.fromLocationId === input.toLocationId) {
    throw ApiError.badRequest('Source and destination locations must differ');
  }
  const quantity = Math.abs(input.quantity);

  return prisma.$transaction(async (tx) => {
    const from = await tx.stockLevel.findUnique({
      where: { productId_locationId: { productId: input.productId, locationId: input.fromLocationId } },
    });
    const available = from?.quantity ?? 0;
    if (available < quantity) {
      throw ApiError.badRequest(
        `Insufficient stock at source: ${available} available, ${quantity} requested`,
        'INSUFFICIENT_STOCK',
        { available, requested: quantity },
      );
    }

    const fromBalance = await applyMovement(tx, {
      type: 'TRANSFER_OUT',
      productId: input.productId,
      locationId: input.fromLocationId,
      quantity: -quantity,
      note: input.note,
      userId: input.userId,
    });
    const toBalance = await applyMovement(tx, {
      type: 'TRANSFER_IN',
      productId: input.productId,
      locationId: input.toLocationId,
      quantity,
      note: input.note,
      userId: input.userId,
    });
    return { fromBalance, toBalance };
  });
}

/** Returns the first active location of a warehouse, creating a MAIN one if needed. */
export async function resolveLocation(tx: Tx, warehouseId: string) {
  const existing = await tx.location.findFirst({
    where: { warehouseId, active: true },
    orderBy: { code: 'asc' },
  });
  if (existing) return existing;
  return tx.location.create({ data: { warehouseId, code: 'MAIN', name: 'Main' } });
}

export interface WarehouseDraw {
  locationId: string;
  quantity: number;
}

export interface DrawFromWarehouseInput {
  warehouseId: string;
  productId: string;
  /** Positive quantity to remove from the warehouse. */
  quantity: number;
  type: MovementType;
  unitCost?: number;
  reference?: string;
  note?: string;
  userId?: string;
}

/**
 * Removes `quantity` of a product from a warehouse, spreading the deduction
 * across its active locations (lowest location code first) so stock is never
 * stranded in one aisle. Throws when the warehouse as a whole is short.
 * Must be called inside a transaction.
 */
export async function drawFromWarehouse(tx: Tx, input: DrawFromWarehouseInput): Promise<WarehouseDraw[]> {
  const { warehouseId, productId, quantity } = input;
  if (quantity <= 0) throw ApiError.badRequest('Quantity must be greater than zero', 'ZERO_MOVEMENT');

  const locations = await tx.location.findMany({
    where: { warehouseId, active: true },
    orderBy: { code: 'asc' },
    select: { id: true },
  });

  const levels = locations.length
    ? await tx.stockLevel.findMany({
        where: {
          productId,
          locationId: { in: locations.map((location) => location.id) },
          quantity: { gt: 0 },
        },
      })
    : [];

  const available = levels.reduce((sum, level) => sum + level.quantity, 0);
  if (available < quantity) {
    throw ApiError.badRequest(
      `Insufficient stock: ${available} available, ${quantity} required`,
      'INSUFFICIENT_STOCK',
      { productId, available, requested: quantity },
    );
  }

  // Consume the lowest-coded location first for a deterministic draw-down.
  const order = new Map(locations.map((location, index) => [location.id, index]));
  levels.sort((a, b) => (order.get(a.locationId) ?? 0) - (order.get(b.locationId) ?? 0));

  const draws: WarehouseDraw[] = [];
  let remaining = quantity;
  for (const level of levels) {
    if (remaining <= 0) break;
    const take = Math.min(level.quantity, remaining);
    await applyMovement(tx, {
      type: input.type,
      productId,
      locationId: level.locationId,
      quantity: -take,
      unitCost: input.unitCost,
      reference: input.reference,
      note: input.note,
      userId: input.userId,
    });
    draws.push({ locationId: level.locationId, quantity: take });
    remaining -= take;
  }

  return draws;
}

export interface CycleCountInput {
  locationId: string;
  items: { productId: string; countedQty: number }[];
  note?: string;
  userId?: string;
}

export async function cycleCount(
  input: CycleCountInput,
): Promise<{ productId: string; expected: number; counted: number; difference: number }[]> {
  return prisma.$transaction(async (tx) => {
    const results: { productId: string; expected: number; counted: number; difference: number }[] = [];
    for (const item of input.items) {
      const level = await tx.stockLevel.findUnique({
        where: { productId_locationId: { productId: item.productId, locationId: input.locationId } },
      });
      const expected = level?.quantity ?? 0;
      const difference = item.countedQty - expected;
      if (difference !== 0) {
        await applyMovement(tx, {
          type: 'CYCLE_COUNT',
          productId: item.productId,
          locationId: input.locationId,
          quantity: difference,
          note: input.note ?? 'Cycle count adjustment',
          userId: input.userId,
        });
      }
      results.push({ productId: item.productId, expected, counted: item.countedQty, difference });
    }
    return results;
  });
}

export interface LowStockRow {
  product: {
    id: string;
    sku: string;
    barcode: string | null;
    name: string;
    unit: string;
    reorderLevel: number;
    costPrice: unknown;
    salePrice: unknown;
    taxRate: unknown;
    categoryId: string | null;
    active: boolean;
    category: { id: string; name: string } | null;
    currency: { id: string; code: string; symbol: string } | null;
  };
  quantity: number;
  shortage: number;
}

/** Products whose total stock has reached or fallen below their reorder level. */
export async function lowStockProducts(warehouseId?: string): Promise<LowStockRow[]> {
  const products = await prisma.product.findMany({
    where: {
      deletedAt: null,
      active: true,
      trackInventory: true,
      reorderLevel: { gt: 0 },
    },
    include: {
      category: { select: { id: true, name: true } },
      currency: { select: { id: true, code: true, symbol: true } },
      stockLevels: { select: { quantity: true, warehouseId: true } },
    },
    orderBy: { name: 'asc' },
  });

  return products
    .map((product) => {
      const levels = warehouseId
        ? product.stockLevels.filter((level) => level.warehouseId === warehouseId)
        : product.stockLevels;
      const quantity = levels.reduce((sum, level) => sum + level.quantity, 0);
      const { stockLevels, ...rest } = product;
      void stockLevels;
      return { product: rest, quantity, shortage: product.reorderLevel - quantity };
    })
    .filter((row) => row.quantity <= row.product.reorderLevel);
}
