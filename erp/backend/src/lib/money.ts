/** Money and quantity helpers. Prisma Decimal columns accept plain numbers on write. */

export const num = (value: unknown): number => {
  if (value === null || value === undefined) return 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
};

export const round2 = (value: number): number =>
  Math.round((value + Number.EPSILON) * 100) / 100;

export interface LineInput {
  quantity: number;
  unitPrice: number;
  discount?: number;
  taxRate?: number;
}

export interface LineTotals {
  net: number;
  tax: number;
  total: number;
}

/** Computes one line's net / tax / total. Discount is a per-line amount. */
export function lineTotals(line: LineInput): LineTotals {
  const gross = round2(num(line.quantity) * num(line.unitPrice));
  const discount = round2(num(line.discount));
  const net = round2(Math.max(0, gross - discount));
  const tax = round2((net * num(line.taxRate)) / 100);
  return { net, tax, total: round2(net + tax) };
}

export interface DocumentTotals {
  subtotal: number;
  discountTotal: number;
  taxTotal: number;
  total: number;
}

export function documentTotals(lines: LineInput[]): DocumentTotals {
  let subtotal = 0;
  let discountTotal = 0;
  let taxTotal = 0;
  for (const line of lines) {
    const t = lineTotals(line);
    subtotal += t.net;
    discountTotal += round2(num(line.discount));
    taxTotal += t.tax;
  }
  return {
    subtotal: round2(subtotal),
    discountTotal: round2(discountTotal),
    taxTotal: round2(taxTotal),
    total: round2(subtotal + taxTotal),
  };
}
