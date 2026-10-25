const fs = require('fs');
const BASE = 'https://abosabry-f7vm.vercel.app/api/v1';

async function json(path, options = {}) {
  const res = await fetch(BASE + path, options);
  const body = await res.json();
  if (!res.ok) throw new Error(path + ' ' + res.status + ' ' + JSON.stringify(body));
  return body;
}

async function main() {
  const login = await json('/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'admin@erp.local', password: 'Password123' }),
  });
  const token = login.data?.accessToken ?? login.accessToken;
  const headers = { Authorization: 'Bearer ' + token, 'X-Tz-Offset': '180' };
  const get = (p) => json(p, { headers });

  const out = { generatedAt: new Date().toISOString(), products: [], movements: {}, users: [], invoices: [], consolidated: null };

  for (const term of ['شاور', 'مكرون']) {
    const rows = (await get('/products?search=' + encodeURIComponent(term) + '&pageSize=50')).data;
    out.products.push(...rows.map((p) => ({
      id: p.id, sku: p.sku, name: p.name, stock: p.stockQuantity,
      cost: p.costPrice, sale: p.salePrice, boxesPerCarton: p.boxesPerCarton,
    })));
  }

  for (const product of out.products) {
    const mv = (await get('/inventory/movements?productId=' + product.id + '&pageSize=200')).data;
    out.movements[product.sku] = mv.map((m) => ({
      createdAt: m.createdAt, type: m.type, quantity: m.quantity,
      reference: m.reference, note: m.note,
      warehouse: m.warehouse?.name ?? m.warehouseId,
      location: m.location?.code ?? m.locationId,
      user: m.user?.name ?? null,
    }));
  }

  const users = (await get('/users/salespersons')).data;
  out.users = users.map((u) => ({ id: u.id, name: u.name, phone: u.phone }));
  const abdo = users.find((u) => u.name.includes('عبده')) ?? users[0];
  out.salesperson = { id: abdo.id, name: abdo.name };

  const from = '2026-10-24T21:00:00.000Z';
  const to = '2026-10-25T20:59:59.999Z';
  const invoices = (await get('/invoices?salespersonId=' + abdo.id + '&from=' + encodeURIComponent(from) + '&to=' + encodeURIComponent(to) + '&pageSize=100')).data;
  out.invoices = [];
  for (const inv of invoices) {
    const detail = (await get('/invoices/' + inv.id)).data;
    out.invoices.push({
      id: detail.id, number: detail.number, status: detail.status,
      issueDate: detail.issueDate, customer: detail.customer?.name ?? 'walk-in',
      salesperson: detail.customer?.salesperson?.name ?? detail.salesOrder?.user?.name ?? null,
      total: detail.total, lines: detail.lines.map((l) => ({
        productId: l.productId, sku: l.product?.sku, name: l.description,
        quantity: l.quantity, sellUnit: l.sellUnit, unitPrice: l.unitPrice, total: l.total,
      })),
    });
  }

  out.consolidated = (await get('/reports/consolidated-sales-note?from=2026-10-25&to=2026-10-25&salespersonId=' + abdo.id + '&tzOffset=180')).data;

  fs.writeFileSync('D:/Default Project/erp/debug-stock.json', JSON.stringify(out, null, 2), 'utf8');
  console.log('WROTE', out.products.length, 'products', out.invoices.length, 'invoices');
}

main().catch((e) => { console.error(e); process.exit(1); });
