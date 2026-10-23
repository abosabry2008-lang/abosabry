"use strict";
/**
 * Human-friendly codes for customers / suppliers (كود العميل / كود المورد).
 *
 * The shop may type its own code; when it leaves the field blank a sequential
 * one is generated (`CUS-0001`, `SUP-0001`, ...) so every record always has a
 * unique, printable code.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.hasCode = void 0;
exports.nextCode = nextCode;
exports.normalizeCode = normalizeCode;
/** Returns true when the caller really typed something. */
const hasCode = (value) => typeof value === 'string' && value.trim().length > 0;
exports.hasCode = hasCode;
/**
 * Builds the next code for a prefix, skipping any value already in `taken`.
 * `existing` is the full set of used codes (case-insensitive).
 */
function nextCode(prefix, existing, width = 4) {
    const used = new Set(Array.from(existing, (code) => code.toUpperCase()));
    let n = 1;
    for (;;) {
        const candidate = `${prefix}-${String(n).padStart(width, '0')}`;
        if (!used.has(candidate.toUpperCase()))
            return candidate;
        n += 1;
    }
}
/** Uppercase, trimmed code with a safe fallback when empty. */
function normalizeCode(value, fallbackPrefix, existing) {
    const trimmed = typeof value === 'string' ? value.trim() : '';
    if (trimmed.length === 0)
        return nextCode(fallbackPrefix, existing);
    return trimmed;
}
//# sourceMappingURL=code.js.map