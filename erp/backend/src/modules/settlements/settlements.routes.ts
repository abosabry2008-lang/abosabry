import { SettlementDirection, SettlementTarget } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok } from '../../lib/http';
import { asBool, asDate, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  cancelSettlement,
  createSettlement,
  getSettlement,
  listSettlements,
  updateSettlement,
} from './settlements.service';

const router = Router();
router.use(authenticate);

const settlementSchema = z.object({
  target: z.nativeEnum(SettlementTarget),
  direction: z.nativeEnum(SettlementDirection).optional(),
  customerId: z.string().nullable().optional(),
  supplierId: z.string().nullable().optional(),
  categoryId: z.string().nullable().optional(),
  amount: z.number().refine((value) => value !== 0, { message: 'Amount cannot be zero' }),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  settledAt: z.coerce.date().nullable().optional(),
});

const updateSchema = z.object({
  direction: z.nativeEnum(SettlementDirection).optional(),
  amount: z.number().optional(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  settledAt: z.coerce.date().nullable().optional(),
});

interface SettlementMoney {
  amount: unknown;
}

const serialize = <T extends SettlementMoney>(settlement: T) => ({
  ...settlement,
  amount: Number(settlement.amount),
});

router.get(
  '/',
  requirePermission('treasury.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const target = asString(query.target) as SettlementTarget | undefined;
    const result = await listSettlements({
      target: target && Object.values(SettlementTarget).includes(target) ? target : undefined,
      customerId: asString(query.customerId),
      supplierId: asString(query.supplierId),
      categoryId: asString(query.categoryId),
      from: asDate(query.from),
      to: asDate(query.to),
      includeCancelled: asBool(query.includeCancelled) === true,
      search: asString(query.search),
      skip: paging.skip,
      take: paging.take,
    });

    res.status(200).json({
      data: result.items.map(serialize),
      meta: {
        page: paging.page,
        pageSize: paging.pageSize,
        total: result.total,
        totalPages: paging.take > 0 ? Math.ceil(result.total / paging.take) : 0,
      },
    });
  }),
);

router.get(
  '/:id',
  requirePermission('treasury.read'),
  asyncHandler(async (req, res) => {
    ok(res, serialize(await getSettlement(req.params.id)));
  }),
);

router.post(
  '/',
  requirePermission('treasury.write'),
  validateBody(settlementSchema),
  asyncHandler(async (req, res) => {
    const settlement = await createSettlement({
      ...req.body,
      userId: currentUser(req).id,
    });
    created(res, serialize(settlement));
  }),
);

router.patch(
  '/:id',
  requirePermission('treasury.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    ok(
      res,
      serialize(
        await updateSettlement(req.params.id, {
          ...req.body,
          userId: currentUser(req).id,
        }),
      ),
    );
  }),
);

router.delete(
  '/:id',
  requirePermission('treasury.write'),
  asyncHandler(async (req, res) => {
    ok(res, serialize(await cancelSettlement(req.params.id, currentUser(req).id)));
  }),
);

export default router;
