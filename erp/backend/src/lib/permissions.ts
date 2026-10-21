import { Role } from '@prisma/client';

export const ALL_PERMISSIONS = [
  'users.read',
  'users.write',
  'roles.manage',
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
    'dashboard',
    'products.read',
    'categories.read',
    'inventory.read',
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
    'reports.read',
    'settings.read',
    'currency.read',
  ],
  CASHIER: [
    'dashboard',
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
    'dashboard',
    'products.read',
    'categories.read',
    'inventory.read',
    'inventory.write',
    'warehouses.read',
    'warehouses.write',
    'suppliers.read',
    'purchasing.read',
    'purchasing.write',
    'reports.read',
    'settings.read',
  ],
  ACCOUNTANT: [
    'dashboard',
    'products.read',
    'suppliers.read',
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

/**
 * Live override map for role defaults, loaded from `Setting.rolePermissions`.
 * When a role is present here, its list fully replaces the built-in default.
 * `ADMIN` is never overridable.
 */
let roleOverrides: Record<string, string[]> = {};

/** Replaces the in-memory role overrides (called on load and settings update). */
export function setRolePermissionOverrides(raw: unknown): void {
  const next: Record<string, string[]> = {};
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    for (const [role, value] of Object.entries(raw as Record<string, unknown>)) {
      if (role === 'ADMIN') continue;
      if (Array.isArray(value)) {
        next[role] = parseCustomPermissions(value);
      }
    }
  }
  roleOverrides = next;
}

/** The permission list a role currently grants, honouring live overrides. */
export function rolePermissions(role: Role): string[] {
  if (role === 'ADMIN') return [...ALL_PERMISSIONS];
  if (Object.prototype.hasOwnProperty.call(roleOverrides, role)) {
    return [...(roleOverrides[role] ?? [])];
  }
  const listed = ROLE_PERMISSIONS[role] ?? [];
  return listed.includes('*') ? [...ALL_PERMISSIONS] : listed;
}

/** Snapshot of the current overrides (for the settings screen). */
export function rolePermissionOverrides(): Record<string, string[]> {
  return { ...roleOverrides };
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
  return Array.from(new Set(rolePermissions(role)));
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
  return rolePermissions(role).includes(permission);
}
