import { Prisma } from '@prisma/client';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { collectionInclude } from '../payments/payments.service';

// ---------------------------------------------------------------------------
// Collection receipts by cash box (إيصالات التحصيل حسب الخزنة)
// ---------------------------------------------------------------------------
//
// Shows, for a chosen period, how much cash each box actually received from
// agent collections — split per box (the receipt box unless a line overrides it)
// so the shop can see the cash that came into every drawer.

export interface CollectionBoxLine {
  customer: string | null;
  invoiceNumber: string | null;
  amount: number;
}

export interface CollectionBoxVoucher {
  id: string;
  number: string;
  collectedAt: string;
  salesperson: string | null;
  total: number;
  lines: CollectionBoxLine[];
}

export interface CollectionBoxGroup {
  cashBoxId: string;
  cashBoxName: string;
  cashBoxCode: string;
  total: number;
  count: number;
  vouchers: CollectionBoxVoucher[];
}

export interface CollectionsByBoxReport {
  from: string | null;
  to: string | null;
  total: number;
  count: number;
  boxes: CollectionBoxGroup[];
}

export async function buildCollectionsByBox(
  fromInput?: Date,
  toInput?: Date,
  cashBoxId?: string,
): Promise<CollectionsByBoxReport> {
  const where: Prisma.CollectionVoucherWhereInput = { cancelledAt: null };
  if (cashBoxId) where.cashBoxId = cashBoxId;
  if (fromInput || toInput) {
    where.collectedAt = {
      ...(fromInput ? { gte: fromInput } : {}),
      ...(toInput ? { lte: toInput } : {}),
    };
  }

  const vouchers = await prisma.collectionVoucher.findMany({
    where,
    include: collectionInclude,
    orderBy: [{ collectedAt: 'asc' }, { createdAt: 'asc' }],
  });

  // A collection line may target its own box; otherwise it belongs to the
  // receipt's box. Group the money by the box the cash actually landed in.
  const byBox = new Map<string, CollectionBoxGroup>();
  let total = 0;
  let count = 0;

  for (const voucher of vouchers) {
    const voucherTotal = round2(Number(voucher.total));
    if (voucherTotal === 0 && voucher.lines.length === 0) continue;
    total = round2(total + voucherTotal);
    count += 1;

    // Split the voucher's lines across the boxes they point at.
    const lineGroups = new Map<string, CollectionBoxLine[]>();
    for (const line of voucher.lines) {
      const box = line.cashBox ?? voucher.cashBox;
      const key = box?.id ?? voucher.cashBoxId;
      const bucket = lineGroups.get(key) ?? [];
      bucket.push({
        customer: line.customer?.name ?? null,
        invoiceNumber: line.invoice?.number ?? null,
        amount: round2(Number(line.amount)),
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
      const lineTotal = round2(lines.reduce((sum, line) => sum + line.amount, 0));
      group.total = round2(group.total + lineTotal);
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
