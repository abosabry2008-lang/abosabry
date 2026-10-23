"use strict";
/** Small helpers for reading untyped Express query values. */
Object.defineProperty(exports, "__esModule", { value: true });
exports.asEnum = exports.asDate = exports.asNumber = exports.asBool = exports.asString = void 0;
const asString = (value) => {
    if (typeof value === 'string') {
        const trimmed = value.trim();
        return trimmed.length > 0 ? trimmed : undefined;
    }
    if (typeof value === 'number')
        return String(value);
    return undefined;
};
exports.asString = asString;
const asBool = (value) => {
    if (value === undefined || value === null || value === '')
        return undefined;
    if (typeof value === 'boolean')
        return value;
    const text = String(value).toLowerCase();
    if (['true', '1', 'yes', 'y'].includes(text))
        return true;
    if (['false', '0', 'no', 'n'].includes(text))
        return false;
    return undefined;
};
exports.asBool = asBool;
const asNumber = (value) => {
    const text = (0, exports.asString)(value);
    if (text === undefined)
        return undefined;
    const parsed = Number(text);
    return Number.isFinite(parsed) ? parsed : undefined;
};
exports.asNumber = asNumber;
const asDate = (value) => {
    const text = (0, exports.asString)(value);
    if (text === undefined)
        return undefined;
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? undefined : date;
};
exports.asDate = asDate;
const asEnum = (value, allowed) => {
    const text = (0, exports.asString)(value);
    if (text === undefined)
        return undefined;
    const upper = text.toUpperCase();
    return allowed.includes(upper) ? upper : undefined;
};
exports.asEnum = asEnum;
//# sourceMappingURL=query.js.map