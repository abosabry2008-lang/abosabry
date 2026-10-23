"use strict";
/** Money and quantity helpers. Prisma Decimal columns accept plain numbers on write. */
Object.defineProperty(exports, "__esModule", { value: true });
exports.round2 = exports.num = void 0;
exports.lineTotals = lineTotals;
exports.documentTotals = documentTotals;
const num = (value) => {
    if (value === null || value === undefined)
        return 0;
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
};
exports.num = num;
const round2 = (value) => Math.round((value + Number.EPSILON) * 100) / 100;
exports.round2 = round2;
/** Computes one line's net / tax / total. Discount is a per-line amount. */
function lineTotals(line) {
    const gross = (0, exports.round2)((0, exports.num)(line.quantity) * (0, exports.num)(line.unitPrice));
    const discount = (0, exports.round2)((0, exports.num)(line.discount));
    const net = (0, exports.round2)(Math.max(0, gross - discount));
    const tax = (0, exports.round2)((net * (0, exports.num)(line.taxRate)) / 100);
    return { net, tax, total: (0, exports.round2)(net + tax) };
}
function documentTotals(lines) {
    let subtotal = 0;
    let discountTotal = 0;
    let taxTotal = 0;
    for (const line of lines) {
        const t = lineTotals(line);
        subtotal += t.net;
        discountTotal += (0, exports.round2)((0, exports.num)(line.discount));
        taxTotal += t.tax;
    }
    return {
        subtotal: (0, exports.round2)(subtotal),
        discountTotal: (0, exports.round2)(discountTotal),
        taxTotal: (0, exports.round2)(taxTotal),
        total: (0, exports.round2)(subtotal + taxTotal),
    };
}
//# sourceMappingURL=money.js.map