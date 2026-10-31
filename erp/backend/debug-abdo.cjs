const BASE = 'https://abosabry-f7vm.vercel.app/api/v1';

async function call(path, options = {}) {
  const res = await fetch(BASE + path, options);
  const text = await res.text();
  let body;
  try { body = JSON.parse(text); } catch { body = text; }
  return { status: res.status, ok: res.ok, body };
}

(async () => {
  const login = await call('/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'abdo@erp.local', password: '12345678' }),
  });
  console.log('LOGIN', JSON.stringify(login, null, 2));
  const token = login.body?.data?.accessToken ?? login.body?.accessToken;
  if (!token) return;

  const headers = { Authorization: 'Bearer ' + token, 'X-Tz-Offset': '180' };
  const endpoints = [
    '/auth/me',
    '/dashboard',
    '/customers?pageSize=5',
    '/suppliers?pageSize=5',
    '/sales-orders?pageSize=5',
    '/invoices?pageSize=5',
    '/products?pageSize=5',
    '/treasury/boxes',
    '/reports/consolidated-sales-note?from=2026-10-25&to=2026-10-25',
    '/reports/customers/balances',
    '/users/salespersons',
  ];
  for (const path of endpoints) {
    const result = await call(path, { headers });
    let summary;
    if (result.ok) {
      const data = result.body?.data;
      if (Array.isArray(data)) summary = `array(${data.length})`;
      else if (data && typeof data === 'object') summary = Object.keys(data).slice(0, 8).join(',');
      else summary = typeof data;
    } else {
      summary = result.body?.error?.message || JSON.stringify(result.body).slice(0, 120);
    }
    console.log(path, '->', result.status, summary);
  }
})().catch((e) => { console.error(e); process.exit(1); });
