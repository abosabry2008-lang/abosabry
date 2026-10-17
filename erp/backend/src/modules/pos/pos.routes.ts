import { PaymentMethod } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created } from '../../lib/http';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { createInvoiceTx, invoiceInclude, issueInvoiceTx } from '../invoices/invoices.service';
import { createPaymentTx } from '../payments/payments.service';
import { registerSaleTx } from '../sales/sales.service';

const router = Router();
router.use(authenticate);

const saleSchema = z.object({
  customerId: z.string().nullable().optional(),
  warehouseId: z.string().min(1),
  currencyId: z.string().nullable().optional(),
  method: z.nativeEnum(PaymentMethod).default('CASH'),
  paidAmount: z.number().min(0),
  reference: z.string().nullable().optional(),
  notes: z.string().nullable().optional(),
  lines: z
    .array(
      z.object({
        productId: z.string().min(1),
        quantity: z.number().int().positive(),
        unitPrice: z.number().min(0).optional(),
        discount: z.number().min(0).optional(),
        taxRate: z.number().min(0).max(100).optional(),
      }),
    )
    .min(1),
});

/**
 * One-shot point-of-sale transaction: creates and fulfils a sales order,
 * raises and issues the invoice, then records the payment - atomically.
 */
router.post(
  '/sale',
  requirePermission('pos.use'),
  validateBody(saleSchema),
  asyncHandler(async (req, res) => {
    const userId = currentUser(req).id;

    const result = await prisma.$transaction(async (tx) => {
      const salesOrder = await registerSaleTx(
        tx,
        {
          customerId: req.body.customerId ?? null,
          warehouseId: req.body.warehouseId,
          currencyId: req.body.currencyId ?? null,
          notes: req.body.notes ?? null,
          channel: 'POS',
          lines: req.body.lines,
        },
        userId,
      );

      const draft = await createInvoiceTx(tx, { salesOrderId: salesOrder.id, userId });
      const invoice = await issueInvoiceTx(tx, draft.id, userId);

      const total = round2(Number(invoice.total));
      const paidAmount = round2(Number(req.body.paidAmount));
      const applied = round2(Math.min(paidAmount, total));

      const payment =
        applied > 0
          ? await createPaymentTx(tx, {
              invoiceId: invoice.id,
              amount: applied,
              method: req.body.method,
              reference: req.body.reference ?? null,
              paidAt: new Date(),
              userId,
            })
          : null;

      const finalInvoice = await tx.invoice.findUnique({
        where: { id: invoice.id },
        include: invoiceInclude,
      });

      return {
        salesOrder,
        invoice: finalInvoice,
        payment,
        change: round2(Math.max(0, paidAmount - total)),
        outstanding: round2(Math.max(0, total - applied)),
      };
    });

    created(res, result);
  }),
);

export default router;
