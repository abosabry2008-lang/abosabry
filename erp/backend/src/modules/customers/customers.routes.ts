import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ACCOUNT, postJournal } from '../accounting/accounting.service';
import { ApiError } from '../../lib/api-error';
import { hasCode, nextCode } from '../../lib/code';
import { asyncHandler, created, getPaging, noContent, ok, paginated } from '../../lib/http';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { asBool, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const schema = z.object({
  code: z.string().max(64).nullable().optional(),
  name: z.string().min(1),
  email: z.string().email().nullable().optional(),
  phone: z.string().nullable().optional(),
  address: z.string().nullable().optional(),
  taxId: z.string().nullable().optional(),
  creditLimit: z.number().min(0).default(0),
  active: z.boolean().default(true),
  salespersonId: z.string().nullable().optional(),
  openingBalance: z.number().optional(),
});

const include = {
  salesperson: { select: { id: true, name: true } },
  _count: { select: { salesOrders: true, invoices: true } },
} satisfies Prisma.CustomerInclude;

function serialize<T extends { creditLimit: unknown; balance: unknown }>(customer: T) {
  return {
    ...customer,
    creditLimit: Number(customer.creditLimit),
    balance: Number(customer.balance),
  };
}

/** Next free `CUS-0001` style code. */
async function generateCustomerCode(): Promise<string> {
  const existing = new Set(
    (await prisma.customer.findMany({ select: { code: true } }))
      .map((c) => c.code)
      .filter((code): code is string => Boolean(code)),
  );
  return nextCode('CUS', existing);
}

router.get(
  '/',
  requirePermission('customers.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 50);
    const search = asString(query.search);
    const active = asBool(query.active);
    const salespersonId = asString(query.salespersonId);

    const where: Prisma.CustomerWhereInput = {
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' } },
              { code: { contains: search, mode: 'insensitive' } },
              { email: { contains: search, mode: 'insensitive' } },
              { phone: { contains: search, mode: 'insensitive' } },
            ],
          }
        : {}),
      ...(active === undefined ? {} : { active }),
      ...(salespersonId ? { salespersonId } : {}),
    };

    const [total, customers] = await Promise.all([
      prisma.customer.count({ where }),
      prisma.customer.findMany({
        where,
        orderBy: { name: 'asc' },
        skip: paging.skip,
        take: paging.take,
        include,
      }),
    ]);
    paginated(res, customers.map((c) => serialize(c)), total, paging);
  }),
);

router.get(
  '/:id',
  requirePermission('customers.read'),
  asyncHandler(async (req, res) => {
    const customer = await prisma.customer.findUnique({ where: { id: req.params.id }, include });
    if (!customer) throw ApiError.notFound('Customer not found');
    ok(res, serialize(customer));
  }),
);

router.post(
  '/',
  requirePermission('customers.write'),
  validateBody(schema),
  asyncHandler(async (req, res) => {
    const { openingBalance, code, ...data } = req.body as any;
    const amount = round2(Number(openingBalance ?? 0));
    const customer = await prisma.$transaction(async (tx) => {
      const resolvedCode = hasCode(code) ? code.trim() : await generateCustomerCode();
      const created = await tx.customer.create({
        data: { ...data, code: resolvedCode },
        include,
      });
      if (amount > 0) {
        await tx.customer.update({
          where: { id: created.id },
          data: { balance: amount },
        });
        await postJournal(tx, {
          memo: `Opening balance for customer ${created.name}`,
          reference: `OB-CUST-${created.id.slice(-6).toUpperCase()}`,
          sourceType: 'OPENING_CUSTOMER',
          sourceId: created.id,
          userId: currentUser(req).id,
          lines: [
            { accountCode: ACCOUNT.RECEIVABLE, debit: amount, description: 'Opening receivable' },
            { accountCode: ACCOUNT.EQUITY, credit: amount, description: 'Opening capital' },
          ],
        });
        const refreshed = await tx.customer.findUnique({ where: { id: created.id }, include });
        return refreshed ?? created;
      }
      return created;
    });
    created(res, serialize(customer));
  }),
);

router.patch(
  '/:id',
  requirePermission('customers.write'),
  validateBody(schema.partial()),
  asyncHandler(async (req, res) => {
    const customer = await prisma.customer.update({ where: { id: req.params.id }, data: req.body, include });
    ok(res, serialize(customer));
  }),
);

router.delete(
  '/:id',
  requirePermission('customers.write'),
  asyncHandler(async (req, res) => {
    const orders = await prisma.salesOrder.count({ where: { customerId: req.params.id } });
    if (orders > 0) {
      await prisma.customer.update({ where: { id: req.params.id }, data: { active: false } });
      noContent(res);
      return;
    }
    await prisma.customer.delete({ where: { id: req.params.id } });
    noContent(res);
  }),
);

export default router;
