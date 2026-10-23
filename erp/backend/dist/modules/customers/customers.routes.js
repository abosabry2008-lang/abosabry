"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const accounting_service_1 = require("../accounting/accounting.service");
const api_error_1 = require("../../lib/api-error");
const code_1 = require("../../lib/code");
const http_1 = require("../../lib/http");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const schema = zod_1.z.object({
    code: zod_1.z.string().max(64).nullable().optional(),
    name: zod_1.z.string().min(1),
    email: zod_1.z.string().email().nullable().optional(),
    phone: zod_1.z.string().nullable().optional(),
    address: zod_1.z.string().nullable().optional(),
    taxId: zod_1.z.string().nullable().optional(),
    creditLimit: zod_1.z.number().min(0).default(0),
    active: zod_1.z.boolean().default(true),
    salespersonId: zod_1.z.string().nullable().optional(),
    openingBalance: zod_1.z.number().optional(),
});
const include = {
    salesperson: { select: { id: true, name: true } },
    _count: { select: { salesOrders: true, invoices: true } },
};
function serialize(customer) {
    return {
        ...customer,
        creditLimit: Number(customer.creditLimit),
        balance: Number(customer.balance),
    };
}
/** Next free `CUS-0001` style code. */
async function generateCustomerCode() {
    const existing = new Set((await prisma_1.prisma.customer.findMany({ select: { code: true } }))
        .map((c) => c.code)
        .filter((code) => Boolean(code)));
    return (0, code_1.nextCode)('CUS', existing);
}
router.get('/', (0, authorize_1.requirePermission)('customers.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 50);
    const search = (0, query_1.asString)(query.search);
    const active = (0, query_1.asBool)(query.active);
    const salespersonId = (0, query_1.asString)(query.salespersonId);
    const where = {
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
        prisma_1.prisma.customer.count({ where }),
        prisma_1.prisma.customer.findMany({
            where,
            orderBy: { name: 'asc' },
            skip: paging.skip,
            take: paging.take,
            include,
        }),
    ]);
    (0, http_1.paginated)(res, customers.map((c) => serialize(c)), total, paging);
}));
router.get('/:id', (0, authorize_1.requirePermission)('customers.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const customer = await prisma_1.prisma.customer.findUnique({ where: { id: req.params.id }, include });
    if (!customer)
        throw api_error_1.ApiError.notFound('Customer not found');
    (0, http_1.ok)(res, serialize(customer));
}));
router.post('/', (0, authorize_1.requirePermission)('customers.write'), (0, validate_1.validateBody)(schema), (0, http_1.asyncHandler)(async (req, res) => {
    const { openingBalance, code, ...data } = req.body;
    const amount = (0, money_1.round2)(Number(openingBalance ?? 0));
    const customer = await prisma_1.prisma.$transaction(async (tx) => {
        const resolvedCode = (0, code_1.hasCode)(code) ? code.trim() : await generateCustomerCode();
        const created = await tx.customer.create({
            data: { ...data, code: resolvedCode },
            include,
        });
        if (amount > 0) {
            await tx.customer.update({
                where: { id: created.id },
                data: { balance: amount },
            });
            await (0, accounting_service_1.postJournal)(tx, {
                memo: `Opening balance for customer ${created.name}`,
                reference: `OB-CUST-${created.id.slice(-6).toUpperCase()}`,
                sourceType: 'OPENING_CUSTOMER',
                sourceId: created.id,
                userId: (0, authenticate_1.currentUser)(req).id,
                lines: [
                    { accountCode: accounting_service_1.ACCOUNT.RECEIVABLE, debit: amount, description: 'Opening receivable' },
                    { accountCode: accounting_service_1.ACCOUNT.EQUITY, credit: amount, description: 'Opening capital' },
                ],
            });
            const refreshed = await tx.customer.findUnique({ where: { id: created.id }, include });
            return refreshed ?? created;
        }
        return created;
    });
    (0, http_1.created)(res, serialize(customer));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('customers.write'), (0, validate_1.validateBody)(schema.partial()), (0, http_1.asyncHandler)(async (req, res) => {
    const customer = await prisma_1.prisma.customer.update({ where: { id: req.params.id }, data: req.body, include });
    (0, http_1.ok)(res, serialize(customer));
}));
router.delete('/:id', (0, authorize_1.requirePermission)('customers.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const orders = await prisma_1.prisma.salesOrder.count({ where: { customerId: req.params.id } });
    if (orders > 0) {
        await prisma_1.prisma.customer.update({ where: { id: req.params.id }, data: { active: false } });
        (0, http_1.noContent)(res);
        return;
    }
    await prisma_1.prisma.customer.delete({ where: { id: req.params.id } });
    (0, http_1.noContent)(res);
}));
exports.default = router;
//# sourceMappingURL=customers.routes.js.map