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
  'returns.edit',
  'returns.cancel',
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
  'openingBalances.read',
  'openingBalances.write',
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
        'openingBalances.write',
        'purchases.cancel',
        'sales.cancel',
        'returns.edit',
        'returns.cancel',
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

export function parseCustomPermissions(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter((p): p is string => typeof p === 'string' && p.length > 0);
}

export function permissionsFor(
  role: Role,
  custom?: unknown,
): string[] {
  if (role === 'ADMIN') return [...ALL_PERMISSIONS];
  const customList = parseCustomPermissions(custom);
  if (customList.length > 0) {
    return Array.from(new Set(customList));
  }
  const listed = ROLE_PERMISSIONS[role] ?? [];
  return listed.includes('*') ? [...ALL_PERMISSIONS] : listed;
}

export function roleHasPermission(
  role: Role,
  permission: Permission,
  custom?: unknown,
): boolean {
  if (role === 'ADMIN') return true;
  const customList = parseCustomPermissions(custom);
  if (customList.length > 0) {
    return customList.includes(permission);
  }
  const listed = ROLE_PERMISSIONS[role] ?? [];
  return listed.includes('*') || listed.includes(permission);
}
