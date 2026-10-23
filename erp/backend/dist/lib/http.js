"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.asyncHandler = void 0;
exports.ok = ok;
exports.created = created;
exports.noContent = noContent;
exports.getPaging = getPaging;
exports.paginated = paginated;
/** Wraps an async route handler so thrown/rejected errors reach the error middleware. */
const asyncHandler = (fn) => (req, res, next) => {
    fn(req, res, next).catch(next);
};
exports.asyncHandler = asyncHandler;
function ok(res, data) {
    res.status(200).json({ data });
}
function created(res, data) {
    res.status(201).json({ data });
}
function noContent(res) {
    res.status(204).end();
}
function getPaging(query, defaultSize = 20, maxSize = 100) {
    const rawPage = Number(query.page ?? 1);
    const rawSize = Number(query.pageSize ?? defaultSize);
    const page = Number.isFinite(rawPage) && rawPage > 0 ? Math.floor(rawPage) : 1;
    const pageSize = Number.isFinite(rawSize) && rawSize > 0 ? Math.min(maxSize, Math.floor(rawSize)) : defaultSize;
    return { page, pageSize, skip: (page - 1) * pageSize, take: pageSize };
}
function paginated(res, data, total, paging) {
    res.status(200).json({
        data,
        meta: {
            page: paging.page,
            pageSize: paging.pageSize,
            total,
            totalPages: paging.take > 0 ? Math.ceil(total / paging.take) : 0,
        },
    });
}
//# sourceMappingURL=http.js.map