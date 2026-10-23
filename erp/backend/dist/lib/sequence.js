"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.nextNumber = nextNumber;
exports.sequenceValue = sequenceValue;
/**
 * Allocates the next document number for a named sequence, e.g. SO-2026-00042.
 * The sequence row is locked/incremented inside the caller's transaction.
 */
async function nextNumber(tx, name, prefix, now = new Date()) {
    const sequence = await tx.sequence.upsert({
        where: { name },
        create: { name, value: 1 },
        update: { value: { increment: 1 } },
    });
    const year = now.getFullYear();
    return `${prefix}-${year}-${String(sequence.value).padStart(5, '0')}`;
}
async function sequenceValue(tx, name) {
    const sequence = await tx.sequence.findUnique({ where: { name } });
    return sequence?.value ?? 0;
}
//# sourceMappingURL=sequence.js.map