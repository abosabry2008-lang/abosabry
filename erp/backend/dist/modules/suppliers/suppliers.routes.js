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
    contact: zod_1.z.string().nullable().optional(),
    email: zod_1.z.string().email().nullable().optional(),
    phone: zod_1.z.string().nullable().optional(),
    address: zod_1.z.string().nullable().optional(),
    taxId: zod_1.z.string().nullable().optional(),
    paymentTermDays: zod_1.z.number().int().min(0).default(30),
    active: zod_1.z.boolean().default(true),
    openingBalance: zod_1.z.number().optional(),
});
/** Next free `SUP-0001` style code. */
async function generateSupplierCode() {
    const existing = new Set((await prisma_1.prisma.supplier.findMany({ select: { code: true } }))
        .map((s) => s.code)
        .filter((code) => Boolean(code)));
    return (0, code_1.nextCode)('SUP', existing);
}
router.get('/', (0, authorize_1.requirePermission)('purchasing.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 50);
    const search = (0, query_1.asString)(query.search);
    const active = (0, query_1.asBool)(query.active);
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
    };
    const [total, suppliers] = await Promise.all([
        prisma_1.prisma.supplier.count({ where }),
        prisma_1.prisma.supplier.findMany({
            where,
            orderBy: { name: 'asc' },
            skip: paging.skip,
            take: paging.take,
            include: { _count: { select: { purchaseOrders: true } } },
        }),
    ]);
    (0, http_1.paginated)(res, suppliers, total, paging);
}));
router.get('/:id', (0, authorize_1.requirePermission)('purchasing.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const supplier = await prisma_1.prisma.supplier.findUnique({
        where: { id: req.params.id },
        include: { _count: { select: { purchaseOrders: true } } },
    });
    if (!supplier)
        throw api_error_1.ApiError.notFound('Supplier not found');
    (0, http_1.ok)(res, supplier);
}));
router.post('/', (0, authorize_1.requirePermission)('purchasing.write'), (0, validate_1.validateBody)(schema), (0, http_1.asyncHandler)(async (req, res) => {
    const { openingBalance, code, ...data } = req.body;
    const amount = (0, money_1.round2)(Number(openingBalance ?? 0));
    const supplier = await prisma_1.prisma.$transaction(async (tx) => {
        const resolvedCode = (0, code_1.hasCode)(code) ? code.trim() : await generateSupplierCode();
        const created = await tx.supplier.create({ data: { ...data, code: resolvedCode } });
        if (amount > 0) {
            await tx.supplier.update({
                where: { id: created.id },
                data: { balance: amount },
            });
            await (0, accounting_service_1.postJournal)(tx, {
                memo: `Opening balance for supplier ${created.name}`,
                reference: `OB-SUPP-${created.id.slice(-6).toUpperCase()}`,
                sourceType: 'OPENING_SUPPLIER',
                sourceId: created.id,
                userId: (0, authenticate_1.currentUser)(req).id,
                lines: [
                    { accountCode: accounting_service_1.ACCOUNT.EQUITY, debit: amount, description: 'Opening capital' },
                    { accountCode: accounting_service_1.ACCOUNT.PAYABLE, credit: amount, description: 'Opening payable' },
                ],
            });
            const refreshed = await tx.supplier.findUnique({ where: { id: created.id } });
            return refreshed ?? created;
        }
        return created;
    });
    (0, http_1.created)(res, supplier);
}));
router.patch('/:id', (0, authorize_1.requirePermission)('purchasing.write'), (0, validate_1.validateBody)(schema.partial()), (0, http_1.asyncHandler)(async (req, res) => {
    const supplier = await prisma_1.prisma.supplier.update({ where: { id: req.params.id }, data: req.body });
    (0, http_1.ok)(res, supplier);
}));
router.delete('/:id', (0, authorize_1.requirePermission)('purchasing.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const orders = await prisma_1.prisma.purchaseOrder.count({ where: { supplierId: req.params.id } });
    if (orders > 0) {
        await prisma_1.prisma.supplier.update({ where: { id: req.params.id }, data: { active: false } });
        (0, http_1.noContent)(res);
        return;
    }
    await prisma_1.prisma.supplier.delete({ where: { id: req.params.id } });
    (0, http_1.noContent)(res);
}));
exports.default = router;
//# sourceMappingURL=suppliers.routes.js.map