import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, ok } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { applyMovement, resolveLocation } from '../inventory/inventory.service';

/**
 * Bulk product import (استيراد الأصناف من Excel).
 *
 * Rows look like `{ name, sku?, price, quantity, costPrice? }`. Matching is by
 * `sku`: an existing code updates the product, a new one is created. When the
 * code column is empty a random code is generated, so the shop only has to type
 * the name, price and quantity.
 */
const router = Router();
router.use(authenticate);

const rowSchema = z.object({
  name: z.string().min(1).max(200),
  sku: z.string().max(64).nullable().optional(),
  barcode: z.string().max(64).nullable().optional(),
  // New import columns as requested: (name, boxesPerCarton, cartonPrice, boxPrice, costPrice, salePrice)
  // Legacy keys 'price' and 'quantity' are still accepted for compatibility.
  price: z.number().min(0).optional(),
  salePrice: z.number().min(0).optional(),
  costPrice: z.number().min(0).optional(),
  quantity: z.number().optional(),
  boxesPerCarton: z.number().int().min(0).optional(),
  cartonPrice: z.number().min(0).optional(),
  boxPrice: z.number().min(0).optional(),
  unit: z.string().max(16).optional(),
});

const importSchema = z.object({
  warehouseId: z.string().min(1).nullable().optional(),
  /** When true, existing products have their stock set to the imported qty. */
  adjustStock: z.boolean().optional(),
  rows: z.array(rowSchema).min(1).max(5000),
});

/** Random, human-readable SKU such as `SKU-7F3K9Q`. */
function randomSku(existing: Set<string>): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (let attempt = 0; attempt < 50; attempt++) {
    let code = '';
    for (let i = 0; i < 6; i++) {
      code += alphabet[Math.floor(Math.random() * alphabet.length)];
    }
    const sku = `SKU-${code}`;
    if (!existing.has(sku)) {
      existing.add(sku);
      return sku;
    }
  }
  // Extremely unlikely: fall back to a timestamp-based code.
  const sku = `SKU-${Date.now().toString(36).toUpperCase()}`;
  existing.add(sku);
  return sku;
}

export interface ImportRowResult {
  name: string;
  sku: string;
  action: 'created' | 'updated' | 'skipped';
  reason?: string;
  stockAdded: number;
}

export interface ImportResult {
  created: number;
  updated: number;
  skipped: number;
  rows: ImportRowResult[];
}

router.post(
  '/import',
  requirePermission('products.write'),
  asyncHandler(async (req, res) => {
    const parsed = importSchema.safeParse(req.body);
    if (!parsed.success) {
      throw ApiError.badRequest('Invalid import payload', 'INVALID_IMPORT', parsed.error.flatten());
    }
    const { rows, warehouseId, adjustStock } = parsed.data;

    // Pre-load existing codes so generated ones never clash.
    const existing = new Set(
      (await prisma.product.findMany({ select: { sku: true } })).map((p) => p.sku),
    );

    // All imported products share one warehouse (the default one when omitted).
    let targetWarehouseId = warehouseId ?? null;
    if (!targetWarehouseId) {
      const first = await prisma.warehouse.findFirst({
        where: { active: true },
        orderBy: { code: 'asc' },
      });
      targetWarehouseId = first?.id ?? null;
    }

    const result = await prisma.$transaction(async (tx) => {
      const out: ImportRowResult[] = [];
      let created = 0;
      let updated = 0;
      let skipped = 0;

      // Resolve the location once, lazily — only when we actually add stock.
      let locationId: string | null = null;
      const location = async (): Promise<string | null> => {
        if (!targetWarehouseId) return null;
        if (!locationId) {
          const resolved = await resolveLocation(tx, targetWarehouseId);
          locationId = resolved.id;
        }
        return locationId;
      };

      for (const row of rows) {
        const name = row.name.trim();
        const code = (row.sku ?? '').trim();
        try {
          const existingProduct = code
            ? await tx.product.findFirst({
                where: { sku: code },
                select: { id: true, deletedAt: true },
              })
            : null;

          if (existingProduct) {
            await tx.product.update({
              where: { id: existingProduct.id },
              data: {
                name,
                deletedAt: null,
                active: true,
                ...(row.costPrice != null ? { costPrice: row.costPrice } : {}),
                ...((row.salePrice ?? row.price) != null
                  ? { salePrice: row.salePrice ?? row.price ?? 0 }
                  : {}),
                ...(row.boxesPerCarton != null ? { boxesPerCarton: row.boxesPerCarton } : {}),
                ...(row.boxPrice != null ? { boxPrice: row.boxPrice } : {}),
                ...(row.cartonPrice != null ? { cartonPrice: row.cartonPrice } : {}),
                ...(row.unit ? { unit: row.unit } : {}),
              },
            });

            let stockAdded = 0;
            // Only touch stock for an existing product when explicitly asked,
            // and never for one that was previously deleted.
            if (adjustStock && row.quantity != null && !existingProduct.deletedAt) {
              const loc = await location();
              if (loc && row.quantity !== 0) {
                const current = await tx.stockLevel.findUnique({
                  where: { productId_locationId: { productId: existingProduct.id, locationId: loc } },
                  select: { quantity: true },
                });
                const delta = row.quantity - (current?.quantity ?? 0);
                if (delta !== 0) {
                  await applyMovement(tx, {
                    type: 'ADJUSTMENT',
                    productId: existingProduct.id,
                    locationId: loc,
                    quantity: delta,
                    unitCost: row.costPrice ?? 0,
                    reference: 'IMPORT',
                    note: 'Stock set by Excel import',
                    userId: currentUser(req).id,
                  });
                  stockAdded = delta;
                }
              }
            }

            updated++;
            out.push({ name, sku: code, action: 'updated', stockAdded });
          } else {
            const sku = code || randomSku(existing);
            const product = await tx.product.create({
              data: {
                sku,
                name,
                unit: row.unit ?? 'pc',
                costPrice: row.costPrice ?? 0,
                salePrice: row.salePrice ?? row.price ?? 0,
                boxesPerCarton: row.boxesPerCarton ?? 0,
                ...(row.boxPrice != null ? { boxPrice: row.boxPrice } : {}),
                ...(row.cartonPrice != null ? { cartonPrice: row.cartonPrice } : {}),
                active: true,
                trackInventory: true,
                ...(row.barcode ? { barcode: row.barcode } : {}),
              },
              select: { id: true },
            });
            existing.add(sku);

            let stockAdded = 0;
            if (row.quantity != null && row.quantity > 0) {
              const loc = await location();
              if (loc) {
                await applyMovement(tx, {
                  type: 'OPENING',
                  productId: product.id,
                  locationId: loc,
                  quantity: row.quantity,
                  unitCost: row.costPrice ?? row.price ?? 0,
                  reference: 'IMPORT',
                  note: 'Opening stock from Excel import',
                  userId: currentUser(req).id,
                });
                stockAdded = row.quantity;
              }
            }

            created++;
            out.push({ name, sku, action: 'created', stockAdded });
          }
        } catch (error) {
          skipped++;
          out.push({
            name,
            sku: code,
            action: 'skipped',
            reason: error instanceof Error ? error.message : 'Unknown error',
            stockAdded: 0,
          });
        }
      }

      return { created, updated, skipped, rows: out };
    });

    ok(res, result);
  }),
);

export default router;
