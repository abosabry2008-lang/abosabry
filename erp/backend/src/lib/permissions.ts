import { Role } from '@prisma/client';

export const ALL_PERMISSIONS = [
  'users.read',
  'users.write',
  'products.read',
  'products.write',
  'categories.read',
  'categories.write',
  'inventory.read',
  'inventory.write',
  'warehouses.read',
  'warehouses.write',
  'purchasing.read',
  'purchasing.write',
  'purchases.cancel',
  'customers.read',
  'customers.write',
  'sales.read',
  'sales.write',
  'sales.cancel',
  'pos.use',
  'invoices.read',
  'invoices.write',
  'invoices.cancel',
  'invoices.edit',
  'payments.read',
  'payments.write',
  'treasury.read',
  'treasury.write',
  'expenses.read',
  'expenses.write',
  'accounting.read',
  'accounting.write',
  'reports.read',
  'settings.read',
  'settings.write',
  'currency.read',
  'currency.write',
] as const;

export type Permission = (typeof ALL_PERMISSIONS)[number];

/** '*' means every permission. */
export const ROLE_PERMISSIONS: Record<Role, string[]> = {
  ADMIN: ['*'],
  MANAGER: (ALL_PERMISSIONS as readonly string[]).filter(
    (p) =>
      ![
        'users.write',
        'settings.write',
        'accounting.write',
        'invoices.cancel',
        'invoices.edit',
        'treasury.write',
        'expenses.write',
        'purchases.cancel',
        'sales.cancel',
      ].includes(p),
  ),
  SALES: [
    'products.read',
    'categories.read',
    'inventory.read',
    'customers.read',
    'customers.write',
    'sales.read',
    'sales.write',
    'pos.use',
    'invoices.read',
    'reports.read',
    'settings.read',
    'currency.read',
    'payments.read',
    'payments.write',
    'treasury.read',
  ],
  CASHIER: [
    'products.read',
    'categories.read',
    'customers.read',
    'customers.write',
    'sales.read',
    'sales.write',
    'pos.use',
    'invoices.read',
    'invoices.write',
    'payments.read',
    'payments.write',
    'treasury.read',
    'expenses.read',
    'reports.read',
    'settings.read',
    'currency.read',
  ],
  WAREHOUSE: [
    'products.read',
    'categories.read',
    'inventory.read',
    'inventory.write',
    'warehouses.read',
    'warehouses.write',
    'purchasing.read',
    'purchasing.write',
    'reports.read',
    'settings.read',
  ],
  ACCOUNTANT: [
    'products.read',
    'purchasing.read',
    'customers.read',
    'sales.read',
    'invoices.read',
    'invoices.write',
    'payments.read',
    'payments.write',
    'treasury.read',
    'expenses.read',
    'accounting.read',
    'accounting.write',
    'reports.read',
    'settings.read',
    'currency.read',
    'currency.write',
  ],
};

export function permissionsFor(role: Role): string[] {
  const listed = ROLE_PERMISSIONS[role] ?? [];
  return listed.includes('*') ? [...ALL_PERMISSIONS] : listed;
}

export function roleHasPermission(role: Role, permission: Permission): boolean {
  const listed = ROLE_PERMISSIONS[role] ?? [];
  return listed.includes('*') || listed.includes(permission);
}
