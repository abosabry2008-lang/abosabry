import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, noContent, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asBool, asString } from '../../lib/query';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { lowStockProducts, totalStockByProduct } from '../inventory/inventory.service';

const router = Router();
router.use(authenticate);

const productSchema = z.object({
  sku: z.string().min(1),
  barcode: z.string().nullable().optional(),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  categoryId: z.string().nullable().optional(),
  currencyId: z.string().nullable().optional(),
  unit: z.string().min(1).default('pc'),
  costPrice: z.number().min(0).default(0),
  salePrice: z.number().min(0).default(0),
  taxRate: z.number().min(0).max(100).default(0),
  reorderLevel: z.number().int().min(0).default(0),
  trackInventory: z.boolean().default(true),
  active: z.boolean().default(true),
  imageUrl: z.string().nullable().optional(),
});

const updateSchema = productSchema.partial();

const include = {
  category: { select: { id: true, name: true } },
  currency: { select: { id: true, code: true, symbol: true } },
} satisfies Prisma.ProductInclude;

type ProductWithRefs = Prisma.ProductGetPayload<{ include: typeof include }>;

interface MoneyLike {
  costPrice: unknown;
  salePrice: unknown;
  taxRate: unknown;
}

function serializeProduct<T extends MoneyLike>(product: T, stockQuantity: number) {
  return {
    ...product,
    costPrice: Number(product.costPrice),
    salePrice: Number(product.salePrice),
    taxRate: Number(product.taxRate),
    stockQuantity,
  };
}

function buildWhere(query: Record<string, unknown>, includeInactive: boolean): Prisma.ProductWhereInput {
  const search = asString(query.search);
  const categoryId = asString(query.categoryId);
  const includeDeleted = asBool(query.includeDeleted) === true;
  const where: Prisma.ProductWhereInput = {};
  // Products that were deleted disappear from the catalogue unless asked for.
  if (!includeDeleted) where.deletedAt = null;
  if (!includeInactive) where.active = true;
  if (categoryId) where.categoryId = categoryId;
  if (search) {
    where.OR = [
      { name: { contains: search, mode: 'insensitive' } },
      { sku: { contains: search, mode: 'insensitive' } },
      { barcode: { contains: search, mode: 'insensitive' } },
    ];
  }
  return where;
}

router.get(
  '/',
  requirePermission('products.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query);
    const includeInactive = asBool(query.includeInactive) === true;
    const lowStock = asBool(query.lowStock) === true;
    const search = asString(query.search);
    const categoryId = asString(query.categoryId);

    if (lowStock) {
      const rows = await lowStockProducts(asString(query.warehouseId));
      const filtered = rows.filter((row) => {
        if (categoryId && row.product.categoryId !== categoryId) return false;
        if (search) {
          const haystack = `${row.product.name} ${row.product.sku} ${row.product.barcode ?? ''}`.toLowerCase();
          if (!haystack.includes(search.toLowerCase())) return false;
        }
        return true;
      });
      const slice = filtered.slice(paging.skip, paging.skip + paging.take);
      paginated(res, slice.map((row) => serializeProduct(row.product, row.quantity)), filtered.length, paging);
      return;
    }

    const where = buildWhere(query, includeInactive);
    const [total, products] = await Promise.all([
      prisma.product.count({ where }),
      prisma.product.findMany({
        where,
        include,
        orderBy: { name: 'asc' },
        skip: paging.skip,
        take: paging.take,
      }),
    ]);

    const stock = await totalStockByProduct(products.map((product) => product.id));
    paginated(
      res,
      products.map((product) => serializeProduct(product, stock.get(product.id) ?? 0)),
      total,
      paging,
    );
  }),
);

router.get(
  '/barcode/:code',
  requirePermission('products.read'),
  asyncHandler(async (req, res) => {
    const product = await prisma.product.findFirst({
      where: { barcode: req.params.code, deletedAt: null },
      include,
    });
    if (!product) throw ApiError.notFound('No product matches that barcode');
    const stock = await totalStockByProduct([product.id]);
    ok(res, serializeProduct(product, stock.get(product.id) ?? 0));
  }),
);

router.get(
  '/:id',
  requirePermission('products.read'),
  asyncHandler(async (req, res) => {
    const product: ProductWithRefs | null = await prisma.product.findFirst({
      where: { id: req.params.id, deletedAt: null },
      include,
    });
    if (!product) throw ApiError.notFound('Product not found');
    const stock = await totalStockByProduct([product.id]);
    ok(res, serializeProduct(product, stock.get(product.id) ?? 0));
  }),
);

router.post(
  '/',
  requirePermission('products.write'),
  validateBody(productSchema),
  asyncHandler(async (req, res) => {
    const product = await prisma.product.create({ data: req.body, include });
    created(res, serializeProduct(product, 0));
  }),
);

router.patch(
  '/:id',
  requirePermission('products.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const existing = await prisma.product.findFirst({ where: { id: req.params.id } });
    if (!existing) throw ApiError.notFound('Product not found');
    const product = await prisma.product.update({
      where: { id: existing.id },
      data: { ...req.body, deletedAt: null },
      include,
    });
    const stock = await totalStockByProduct([product.id]);
    ok(res, serializeProduct(product, stock.get(product.id) ?? 0));
  }),
);

// Restores a soft-deleted product back into the catalogue.
router.post(
  '/:id/restore',
  requirePermission('products.write'),
  asyncHandler(async (req, res) => {
    const existing = await prisma.product.findFirst({ where: { id: req.params.id } });
    if (!existing) throw ApiError.notFound('Product not found');
    const product = await prisma.product.update({
      where: { id: existing.id },
      data: { deletedAt: null, active: true },
      include,
    });
    const stock = await totalStockByProduct([product.id]);
    ok(res, serializeProduct(product, stock.get(product.id) ?? 0));
  }),
);

router.delete(
  '/:id',
  requirePermission('products.write'),
  asyncHandler(async (req, res) => {
    const existing = await prisma.product.findFirst({ where: { id: req.params.id, deletedAt: null } });
    if (!existing) throw ApiError.notFound('Product not found');
    // Soft delete keeps historical orders and movements intact.
    await prisma.product.update({
      where: { id: existing.id },
      data: { deletedAt: new Date(), active: false },
    });
    noContent(res);
  }),
);

export default router;
