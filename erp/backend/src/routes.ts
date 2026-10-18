import { Router } from 'express';
import accountingRoutes from './modules/accounting/accounting.routes';
import authRoutes from './modules/auth/auth.routes';
import categoriesRoutes from './modules/categories/categories.routes';
import currencyRoutes from './modules/currency/currency.routes';
import customersRoutes from './modules/customers/customers.routes';
import inventoryRoutes from './modules/inventory/inventory.routes';
import invoicesRoutes from './modules/invoices/invoices.routes';
import paymentsRoutes from './modules/payments/payments.routes';
import posRoutes from './modules/pos/pos.routes';
import printingRoutes from './modules/printing/printing.routes';
import productsRoutes from './modules/products/products.routes';
import purchasingRoutes from './modules/purchasing/purchasing.routes';
import reportsRoutes from './modules/reports/reports.routes';
import returnsRoutes from './modules/returns/returns.routes';
import salesRoutes from './modules/sales/sales.routes';
import settingsRoutes from './modules/settings/settings.routes';
import suppliersRoutes from './modules/suppliers/suppliers.routes';
import usersRoutes from './modules/users/users.routes';
import { locationsRouter, warehousesRouter } from './modules/warehouses/warehouses.routes';

const api = Router();

api.get('/health', (_req, res) => {
  res.json({ status: 'ok', version: '1.0.0' });
});

api.use('/auth', authRoutes);
api.use('/users', usersRoutes);
api.use('/categories', categoriesRoutes);
api.use('/products', productsRoutes);
api.use('/warehouses', warehousesRouter);
api.use('/locations', locationsRouter);
api.use('/inventory', inventoryRoutes);
api.use('/suppliers', suppliersRoutes);
api.use('/purchase-orders', purchasingRoutes);
api.use('/customers', customersRoutes);
api.use('/sales-orders', salesRoutes);
api.use('/returns', returnsRoutes);
api.use('/pos', posRoutes);
api.use('/invoices', invoicesRoutes);
api.use('/payments', paymentsRoutes);
api.use('/currencies', currencyRoutes);
api.use('/reports', reportsRoutes);
api.use('/print', printingRoutes);
api.use('/accounting', accountingRoutes);
api.use('/settings', settingsRoutes);

export default api;
