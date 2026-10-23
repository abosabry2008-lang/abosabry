"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCollectionsByBox = buildCollectionsByBox;
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const payments_service_1 = require("../payments/payments.service");
async function buildCollectionsByBox(fromInput, toInput, cashBoxId) {
    const where = { cancelledAt: null };
    if (cashBoxId)
        where.cashBoxId = cashBoxId;
    if (fromInput || toInput) {
        where.collectedAt = {
            ...(fromInput ? { gte: fromInput } : {}),
            ...(toInput ? { lte: toInput } : {}),
        };
    }
    const vouchers = await prisma_1.prisma.collectionVoucher.findMany({
        where,
        include: payments_service_1.collectionInclude,
        orderBy: [{ collectedAt: 'asc' }, { createdAt: 'asc' }],
    });
    // A collection line may target its own box; otherwise it belongs to the
    // receipt's box. Group the money by the box the cash actually landed in.
    const byBox = new Map();
    let total = 0;
    let count = 0;
    for (const voucher of vouchers) {
        const voucherTotal = (0, money_1.round2)(Number(voucher.total));
        if (voucherTotal === 0 && voucher.lines.length === 0)
            continue;
        total = (0, money_1.round2)(total + voucherTotal);
        count += 1;
        // Split the voucher's lines across the boxes they point at.
        const lineGroups = new Map();
        for (const line of voucher.lines) {
            const box = line.cashBox ?? voucher.cashBox;
            const key = box?.id ?? voucher.cashBoxId;
            const bucket = lineGroups.get(key) ?? [];
            bucket.push({
                customer: line.customer?.name ?? null,
                invoiceNumber: line.invoice?.number ?? null,
                amount: (0, money_1.round2)(Number(line.amount)),
            });
            lineGroups.set(key, bucket);
        }
        // Fallback when the voucher has no lines but still carries a total.
        if (lineGroups.size === 0) {
            lineGroups.set(voucher.cashBoxId, []);
        }
        for (const [key, lines] of lineGroups) {
            const box = lines.length === 0 ? voucher.cashBox : undefined;
            const group = byBox.get(key) ?? {
                cashBoxId: key,
                cashBoxName: box?.name ?? voucher.cashBox.name,
                cashBoxCode: box?.code ?? voucher.cashBox.code,
                total: 0,
                count: 0,
                vouchers: [],
            };
            const lineTotal = (0, money_1.round2)(lines.reduce((sum, line) => sum + line.amount, 0));
            group.total = (0, money_1.round2)(group.total + lineTotal);
            group.count += 1;
            group.vouchers.push({
                id: voucher.id,
                number: voucher.number,
                collectedAt: voucher.collectedAt.toISOString(),
                salesperson: voucher.salesperson?.name ?? null,
                total: lineTotal,
                lines,
            });
            byBox.set(key, group);
        }
    }
    return {
        from: fromInput ? fromInput.toISOString() : null,
        to: toInput ? toInput.toISOString() : null,
        total,
        count,
        boxes: [...byBox.values()].sort((a, b) => b.total - a.total),
    };
}
//# sourceMappingURL=collections.service.js.map