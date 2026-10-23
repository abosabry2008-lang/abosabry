import { Prisma, Role } from '@prisma/client';
import { ApiError } from './api-error';
import { prisma } from './prisma';

/**
 * Sales representatives may only work with the customers assigned to them.
 *
 * The checks live in one place so customer lists, sales orders, invoices,
 * payments and reports all apply exactly the same ownership rule. Managers,
 * administrators and the other back-office roles are unaffected.
 */
export interface ScopeUser {
  id: string;
  role: Role | string;
}

export function isSalesperson(user?: ScopeUser | null): boolean {
  return String(user?.role ?? '').toUpperCase() === 'SALES';
}

export function canViewProfit(user?: ScopeUser | null): boolean {
  const role = String(user?.role ?? '').toUpperCase();
  return role === 'ADMIN' || role === 'MANAGER';
}

/** The salesperson id the current user is allowed to query. */
export function scopedSalespersonId(
  user: ScopeUser,
  requested?: string | null,
): string | undefined {
  if (isSalesperson(user)) return user.id;
  return requested || undefined;
}

/** Customer list/balance scope: SALES only sees their assigned customers. */
export function customerAccessWhere(
  user: ScopeUser,
): Prisma.CustomerWhereInput | null {
  return isSalesperson(user) ? { salespersonId: user.id } : null;
}

/**
 * Sales orders belong to a salesperson when the customer is assigned to them,
 * or when it is a walk-in order they created themselves.
 */
export function salesOrderAccessWhere(
  user: ScopeUser,
): Prisma.SalesOrderWhereInput | null {
  if (!isSalesperson(user)) return null;
  return {
    OR: [
      { customer: { salespersonId: user.id } },
      { customerId: null, userId: user.id },
    ],
  };
}

/** Invoices belong to a salesperson through their customer or source order. */
export function invoiceAccessWhere(
  user: ScopeUser,
): Prisma.InvoiceWhereInput | null {
  if (!isSalesperson(user)) return null;
  return {
    OR: [
      { customer: { salespersonId: user.id } },
      { customerId: null, salesOrder: { userId: user.id } },
    ],
  };
}

export async function assertCustomerAccess(
  user: ScopeUser,
  customerId?: string | null,
): Promise<void> {
  if (!isSalesperson(user) || !customerId) return;
  const customer = await prisma.customer.findUnique({
    where: { id: customerId },
    select: { salespersonId: true },
  });
  // A missing customer is reported as 404 by the calling service/route.
  if (customer && customer.salespersonId !== user.id) {
    throw ApiError.forbidden(
      'You can only work with customers assigned to you',
      'CUSTOMER_NOT_ASSIGNED',
    );
  }
}

export async function assertSalesOrderAccess(
  user: ScopeUser,
  orderId: string,
): Promise<void> {
  if (!isSalesperson(user)) return;
  const order = await prisma.salesOrder.findUnique({
    where: { id: orderId },
    select: {
      userId: true,
      customerId: true,
      customer: { select: { salespersonId: true } },
    },
  });
  if (!order) return;
  const ownsCustomer = order.customer?.salespersonId === user.id;
  const ownsWalkIn = order.customerId == null && order.userId === user.id;
  if (!ownsCustomer && !ownsWalkIn) {
    throw ApiError.forbidden(
      'You can only work with your own sales orders',
      'SALES_ORDER_NOT_ASSIGNED',
    );
  }
}

export async function assertInvoiceAccess(
  user: ScopeUser,
  invoiceId: string,
): Promise<void> {
  if (!isSalesperson(user)) return;
  const invoice = await prisma.invoice.findUnique({
    where: { id: invoiceId },
    select: {
      customerId: true,
      customer: { select: { salespersonId: true } },
      salesOrder: { select: { userId: true } },
    },
  });
  if (!invoice) return;
  const ownsCustomer = invoice.customer?.salespersonId === user.id;
  const ownsWalkIn =
    invoice.customerId == null && invoice.salesOrder?.userId === user.id;
  if (!ownsCustomer && !ownsWalkIn) {
    throw ApiError.forbidden(
      'You can only work with your own invoices',
      'INVOICE_NOT_ASSIGNED',
    );
  }
}
