import type { NextFunction, Request, RequestHandler, Response } from 'express';

export type AsyncHandler = (req: Request, res: Response, next: NextFunction) => Promise<unknown>;

/** Wraps an async route handler so thrown/rejected errors reach the error middleware. */
export const asyncHandler =
  (fn: AsyncHandler): RequestHandler =>
  (req, res, next) => {
    fn(req, res, next).catch(next);
  };

export function ok(res: Response, data: unknown): void {
  res.status(200).json({ data });
}

export function created(res: Response, data: unknown): void {
  res.status(201).json({ data });
}

export function noContent(res: Response): void {
  res.status(204).end();
}

export interface Paging {
  page: number;
  pageSize: number;
  skip: number;
  take: number;
}

export function getPaging(
  query: Record<string, unknown>,
  defaultSize = 20,
  maxSize = 100,
): Paging {
  const rawPage = Number(query.page ?? 1);
  const rawSize = Number(query.pageSize ?? defaultSize);
  const page = Number.isFinite(rawPage) && rawPage > 0 ? Math.floor(rawPage) : 1;
  const pageSize = Number.isFinite(rawSize) && rawSize > 0 ? Math.min(maxSize, Math.floor(rawSize)) : defaultSize;
  return { page, pageSize, skip: (page - 1) * pageSize, take: pageSize };
}

export function paginated(
  res: Response,
  data: unknown[],
  total: number,
  paging: Paging,
): void {
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
