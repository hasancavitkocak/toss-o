// toss-o yönetim paneli (bağımlılıksız). Kullanıcı verisi her zaman
// esc() ile kaçışlanarak basılır; satır içi kod yok (CSP).
'use strict';

const $ = (s, el = document) => el.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
const fmt = (n) => Number(n ?? 0).toLocaleString('tr-TR');
const dt = (v) => (v ? new Date(v).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' }) : '—');
const day = (v) => new Date(v).toLocaleDateString('tr-TR', { day: '2-digit', month: '2-digit' });

const ACTIONS = {
  credits: 'Hak değişikliği', ban: 'Askıya alma', unban: 'Askı kaldırma', admin_on: 'Admin yapıldı',
  admin_off: 'Admin yetkisi alındı', delete_user: 'Hesap silindi', revoke_purchase: 'Satın alma iadesi',
  product_add: 'Paket eklendi', product_edit: 'Paket düzenlendi', settings: 'Ayar değişti',
};
const COSTS = { daily: 'Günlük ücretsiz', reply: 'Ücretsiz cevap', credit: 'Satın alınan hak', bot: 'Bot cevabı', legacy: 'Eski' };

// ---------- oturum ve API ----------
let token = sessionStorage.getItem('tosso_admin');

async function api(method, path, body) {
  const res = await fetch(`/api/admin${path}`, {
    method,
    headers: {
      ...(token && { authorization: `Bearer ${token}` }),
      ...(body && { 'content-type': 'application/json' }),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (res.status === 401 || res.status === 403) {
    if (path !== '/login') logout();
  }
  if (!res.ok) throw new Error(data?.error ?? 'Beklenmeyen bir hata oluştu.');
  return data;
}

function logout() {
  token = null;
  sessionStorage.removeItem('tosso_admin');
  $('#app').hidden = true;
  $('#login').hidden = false;
}

let toastTimer;
function toast(text, bad = false) {
  const t = $('#toast');
  t.textContent = text;
  t.className = bad ? 'toast bad' : 'toast';
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 3200);
}

/** Onay / metin girişi penceresi: girdi varsa metni, yoksa true döner; vazgeçince null */
function ask({ title, text = '', input = null, ok = 'Tamam', danger = false }) {
  const d = $('#dialog');
  $('#dialog-title').textContent = title;
  $('#dialog-text').textContent = text;
  const lab = $('#dialog-label');
  lab.hidden = !input;
  if (input) {
    lab.querySelector('span').textContent = input.label;
    $('#dialog-input').value = input.value ?? '';
    $('#dialog-input').placeholder = input.placeholder ?? '';
  }
  $('#dialog-ok').textContent = ok;
  $('#dialog-ok').className = danger ? 'btn danger' : 'btn primary';
  d.returnValue = '';
  d.showModal();
  if (input) $('#dialog-input').focus();
  return new Promise((resolve) => {
    d.addEventListener('close', () => {
      if (d.returnValue !== 'ok') return resolve(null);
      resolve(input ? $('#dialog-input').value.trim() : true);
    }, { once: true });
  });
}

// ---------- yönlendirme ----------
const view = () => $('#view');
const routes = {
  '': dashboard,
  users: users,
  purchases: purchases,
  products: products,
  settings: settings,
  log: logPage,
};

async function route() {
  const [, name = '', id] = location.hash.replace(/^#\/?/, '#/').split('/');
  for (const a of document.querySelectorAll('#nav a')) a.classList.toggle('active', a.dataset.route === name);
  view().innerHTML = '<p class="muted">Yükleniyor…</p>';
  try {
    if (name === 'users' && id) await userDetail(id);
    else await (routes[name] ?? dashboard)();
  } catch (e) {
    view().innerHTML = `<p class="error">${esc(e.message)}</p>`;
  }
}

function pager(total, page, pageSize, go) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const el = document.createElement('div');
  el.className = 'pager';
  el.innerHTML = `<span class="muted">${fmt(total)} kayıt · sayfa ${page + 1}/${pages}</span>
    <button class="btn small" data-p="${page - 1}" ${page <= 0 ? 'disabled' : ''}>‹ Önceki</button>
    <button class="btn small" data-p="${page + 1}" ${page + 1 >= pages ? 'disabled' : ''}>Sonraki ›</button>`;
  el.addEventListener('click', (e) => {
    const p = e.target.dataset?.p;
    if (p !== undefined && !e.target.disabled) go(Number(p));
  });
  return el;
}

// ---------- gösterge ----------
function barChart(days, key, cls) {
  const max = Math.max(1, ...days.map((d) => d[key]));
  const w = 700, h = 160, gap = 6, bw = (w - gap * (days.length - 1)) / days.length;
  const bars = days.map((d, i) => {
    const bh = Math.round((d[key] / max) * (h - 30));
    const x = i * (bw + gap);
    return `<rect class="bar ${cls}" x="${x}" y="${h - 16 - bh}" width="${bw}" height="${Math.max(bh, 1)}" rx="3"></rect>
      <text x="${x + bw / 2}" y="${h - 3}" text-anchor="middle">${esc(day(d.day))}</text>
      ${d[key] ? `<text x="${x + bw / 2}" y="${h - 20 - bh}" text-anchor="middle">${d[key]}</text>` : ''}`;
  }).join('');
  return `<svg class="chart" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">${bars}</svg>`;
}

async function dashboard() {
  const s = await api('GET', '/stats');
  const card = (k, v, sub = '') => `<div class="card"><div class="k">${k}</div><div class="v">${fmt(v)}</div>${sub ? `<div class="s">${sub}</div>` : ''}</div>`;
  view().innerHTML = `
    <h1>Gösterge</h1>
    <div class="cards">
      ${card('Kullanıcı', s.users, `+${fmt(s.users_1d)} bugün · +${fmt(s.users_7d)} bu hafta`)}
      ${card('Aktif (7 gün)', s.active_7d, 'mektup gönderen')}
      ${card('Mektup', s.letters, `${fmt(s.letters_1d)} son 24 saatte`)}
      ${card('Şu an yolda', s.in_flight, 'henüz varmamış uçak')}
      ${card('Arkadaşlık', s.friendships)}
      ${card('Satın alma', s.purchases, `${fmt(s.test_purchases)} test satın alma`)}
      ${card('Satılan hak', s.credits_sold, `${fmt(s.credits_used)} tanesi kullanıldı`)}
      ${card('Bekleyen bakiye', s.credits_outstanding, 'kullanıcılardaki toplam hak')}
      ${card('Askıdaki hesap', s.banned)}
    </div>
    <div class="panel">
      <div class="row"><h2>Son 14 gün</h2><span class="spacer"></span>
        <div class="legend" id="series">
          <button class="btn small primary" data-k="letters">Mektup</button>
          <button class="btn small" data-k="signups">Kayıt</button>
          <button class="btn small" data-k="purchases">Satın alma</button>
        </div></div>
      <div id="chart">${barChart(s.days, 'letters', '')}</div>
    </div>
    <div class="panel">
      <h2>Mektupların bedeli</h2>
      <table><thead><tr><th>Tür</th><th class="num">Adet</th></tr></thead><tbody>
        ${s.costs.map((c) => `<tr><td>${esc(COSTS[c.cost] ?? c.cost)}</td><td class="num">${fmt(c.n)}</td></tr>`).join('')}
      </tbody></table>
    </div>`;
  $('#series').addEventListener('click', (e) => {
    const k = e.target.dataset?.k;
    if (!k) return;
    for (const b of $('#series').children) b.classList.toggle('primary', b === e.target);
    $('#chart').innerHTML = barChart(s.days, k, { letters: '', signups: 'green', purchases: 'red' }[k]);
  });
}

// ---------- kullanıcılar ----------
const userState = { q: '', filter: 'all', page: 0 };

function statusBadges(u) {
  return [
    u.isAdmin && '<span class="badge navy">admin</span>',
    u.isBot && '<span class="badge">bot</span>',
    u.bannedAt && '<span class="badge red">askıda</span>',
  ].filter(Boolean).join('');
}

async function users() {
  view().innerHTML = `
    <h1>Kullanıcılar</h1>
    <div class="panel">
      <form class="row" id="user-search">
        <input name="q" placeholder="kullanıcı adı, isim ya da il ara" value="${esc(userState.q)}">
        <select name="filter">
          ${[['all', 'Tümü'], ['buyers', 'Satın alanlar'], ['banned', 'Askıdakiler'], ['admin', 'Adminler'], ['bots', 'Botlar']]
            .map(([v, l]) => `<option value="${v}" ${userState.filter === v ? 'selected' : ''}>${l}</option>`).join('')}
        </select>
        <button class="btn primary">Ara</button>
      </form>
      <div class="table-wrap" id="user-table"></div>
    </div>`;
  $('#user-search').addEventListener('submit', (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    Object.assign(userState, { q: f.get('q'), filter: f.get('filter'), page: 0 });
    loadUsers();
  });
  await loadUsers();
}

async function loadUsers() {
  const { q, filter, page } = userState;
  const r = await api('GET', `/users?q=${encodeURIComponent(q)}&filter=${filter}&page=${page}`);
  const box = $('#user-table');
  box.innerHTML = `<table><thead><tr>
      <th>Kullanıcı</th><th>İl</th><th class="num">Hak</th><th class="num">Gönderdi</th>
      <th class="num">Aldı</th><th class="num">Arkadaş</th><th>Son mektup</th><th>Kayıt</th></tr></thead>
    <tbody>${r.users.map((u) => `<tr class="click" data-id="${esc(u.id)}">
      <td><b>${esc(u.displayName)}</b> <span class="muted">@${esc(u.username)}</span>${statusBadges(u)}</td>
      <td>${esc(u.city)}</td><td class="num">${fmt(u.bonus)}</td><td class="num">${fmt(u.sent)}</td>
      <td class="num">${fmt(u.received)}</td><td class="num">${fmt(u.friends)}</td>
      <td>${dt(u.lastLetterAt)}</td><td>${dt(u.createdAt)}</td></tr>`).join('')
      || '<tr><td colspan="8" class="muted">Kimse bulunamadı.</td></tr>'}</tbody></table>`;
  box.querySelector('tbody').addEventListener('click', (e) => {
    const tr = e.target.closest('tr[data-id]');
    if (tr) location.hash = `#/users/${tr.dataset.id}`;
  });
  box.append(pager(r.total, r.page, r.pageSize, (p) => { userState.page = p; loadUsers(); }));
}

async function userDetail(id) {
  const d = await api('GET', `/users/${encodeURIComponent(id)}`);
  const u = d.user;
  const c = d.counts;
  view().innerHTML = `
    <a href="#/users" class="back">‹ Kullanıcılar</a>
    <div class="row"><h1>${esc(u.displayName)} <span class="muted">@${esc(u.username)}</span>${statusBadges(u)}</h1></div>
    ${u.bannedAt ? `<p class="error">Askıda (${dt(u.bannedAt)}): ${esc(u.banReason)}</p>` : ''}
    <div class="grid2">
      <div class="panel">
        <h2>Mektup hakları</h2>
        <dl class="kv">
          <dt>Bugünkü ücretsiz</dt><dd>${fmt(d.credits.dailyLeft)} / ${fmt(d.credits.dailyFree)}</dd>
          <dt>Satın alınmış / tanımlı</dt><dd id="bonus">${fmt(d.credits.bonus)}</dd>
        </dl>
        <form class="row" id="credit-form">
          <input name="amount" type="number" step="1" placeholder="+10 ya da -5" required>
          <input name="reason" placeholder="gerekçe (zorunlu)" required minlength="3">
          <button class="btn primary">Uygula</button>
        </form>
        <p class="note">Eksi değer hak düşer; bakiye sıfırın altına inmez. Her değişiklik kaydedilir.</p>
      </div>
      <div class="panel">
        <h2>Hesap</h2>
        <dl class="kv">
          <dt>Konum</dt><dd>${esc([u.place, u.city].filter(Boolean).join(', '))}</dd>
          <dt>Kayıt</dt><dd>${dt(u.createdAt)}</dd>
          <dt>Yasal metin onayı</dt><dd>${esc(u.legalVersion ?? '—')} · ${dt(u.termsAcceptedAt)}</dd>
          <dt>Profil fotoğrafı</dt><dd>${u.hasPhoto ? 'var' : 'yok'}</dd>
        </dl>
        <div class="row" id="account-actions">
          ${u.bannedAt
            ? '<button class="btn" data-a="unban">Askıyı kaldır</button>'
            : '<button class="btn danger" data-a="ban">Askıya al</button>'}
          ${u.isBot ? '' : `<button class="btn" data-a="admin">${u.isAdmin ? 'Admin yetkisini al' : 'Admin yap'}</button>`}
          <span class="spacer"></span>
          <button class="btn danger" data-a="delete">Hesabı sil</button>
        </div>
      </div>
    </div>
    <div class="cards">
      ${[['Gönderdiği', c.sent], ['Aldığı', c.received], ['Yolda', c.in_flight], ['Rastgele', c.random_sent],
         ['Arkadaş', c.friends], ['Bekleyen istek', c.pending_requests], ['Engellediği', c.blocking], ['Onu engelleyen', c.blocked_by]]
        .map(([k, v]) => `<div class="card"><div class="k">${k}</div><div class="v">${fmt(v)}</div></div>`).join('')}
    </div>
    <div class="panel"><h2>Satın almalar</h2><div class="table-wrap">${purchaseTable(d.purchases, false)}</div></div>
    <div class="grid2">
      <div class="panel"><h2>Hak hareketleri</h2>
        <table><thead><tr><th>Tarih</th><th class="num">Miktar</th><th>Gerekçe</th><th>Admin</th></tr></thead><tbody>
        ${d.grants.map((g) => `<tr><td>${dt(g.created_at)}</td><td class="num">${g.amount > 0 ? '+' : ''}${fmt(g.amount)}</td>
          <td>${esc(g.reason)}</td><td>${esc(g.admin ?? '—')}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Yok</td></tr>'}
        </tbody></table></div>
      <div class="panel"><h2>Son mektuplar</h2>
        <p class="note">Gizlilik gereği mektup içerikleri gösterilmez.</p>
        <table><thead><tr><th>Yön</th><th>Kişi</th><th>Gönderim</th><th>Durum</th><th>Bedel</th></tr></thead><tbody>
        ${d.recentLetters.map((l) => `<tr><td>${l.dir === 'out' ? '→ giden' : '← gelen'}</td><td>@${esc(l.other)}${l.is_random ? '<span class="badge">rastgele</span>' : ''}</td>
          <td>${dt(l.sent_at)}</td><td>${new Date(l.deliver_at) > new Date() ? '<span class="badge amber">yolda</span>' : l.opened_at ? '<span class="badge green">okundu</span>' : '<span class="badge">ulaştı</span>'}</td>
          <td>${esc(COSTS[l.cost] ?? l.cost)}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Yok</td></tr>'}
        </tbody></table></div>
    </div>
    <div class="panel"><h2>Bu hesaptaki işlemler</h2>${logTable(d.log)}</div>`;

  $('#credit-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const amount = Number(f.get('amount'));
    if (!Number.isInteger(amount) || amount === 0) return toast('Sıfır olmayan bir tam sayı yaz.', true);
    try {
      const r = await api('POST', `/users/${u.id}/credits`, { amount, reason: f.get('reason') });
      toast(`Yeni bakiye: ${fmt(r.bonus)} hak`);
      userDetail(u.id);
    } catch (err) { toast(err.message, true); }
  });

  $('#account-actions').addEventListener('click', async (e) => {
    const a = e.target.dataset?.a;
    if (!a) return;
    try {
      if (a === 'ban') {
        const reason = await ask({ title: 'Hesabı askıya al', text: 'Kullanıcı giriş yapamaz, mektup ya da istek gönderemez, eşleşmelerde görünmez.',
          input: { label: 'Gerekçe', placeholder: 'ör. taciz şikâyeti' }, ok: 'Askıya al', danger: true });
        if (!reason) return;
        await api('POST', `/users/${u.id}/ban`, { reason });
        toast('Hesap askıya alındı');
      } else if (a === 'unban') {
        if (!(await ask({ title: 'Askıyı kaldır', text: `@${u.username} yeniden giriş yapabilecek.` }))) return;
        await api('DELETE', `/users/${u.id}/ban`);
        toast('Askı kaldırıldı');
      } else if (a === 'admin') {
        const on = !u.isAdmin;
        if (!(await ask({ title: on ? 'Admin yap' : 'Admin yetkisini al',
          text: on ? `@${u.username} bu panele tam erişim kazanacak.` : `@${u.username} artık panele giremeyecek.`, danger: on }))) return;
        await api('PUT', `/users/${u.id}/admin`, { isAdmin: on });
        toast('Yetki güncellendi');
      } else if (a === 'delete') {
        const confirm = await ask({ title: 'Hesabı kalıcı olarak sil', danger: true, ok: 'Sil',
          text: 'Mektupları, arkadaşlıkları, satın alma kayıtları ve fotoğrafı silinir. Geri alınamaz.',
          input: { label: `Onaylamak için "${u.username}" yaz` } });
        if (!confirm) return;
        await api('DELETE', `/users/${u.id}`, { confirm });
        toast('Hesap silindi');
        location.hash = '#/users';
        return;
      }
      userDetail(u.id);
    } catch (err) { toast(err.message, true); }
  });
  bindRevoke(() => userDetail(u.id));
}

// ---------- satın almalar ----------
const PLATFORM = { google: 'Google Play', test: 'Test' };

function purchaseTable(rows, withUser = true) {
  return `<table><thead><tr><th>Tarih</th>${withUser ? '<th>Kullanıcı</th>' : ''}<th>Paket</th>
    <th class="num">Hak</th><th>Kanal</th><th>Sipariş no</th><th>Durum</th><th></th></tr></thead><tbody>
    ${rows.map((p) => `<tr><td>${dt(p.created_at)}</td>
      ${withUser ? `<td><a href="#/users/${esc(p.user_id)}">@${esc(p.username)}</a></td>` : ''}
      <td>${esc(p.product_id)}</td><td class="num">${fmt(p.credits)}</td><td>${esc(PLATFORM[p.platform] ?? p.platform)}</td>
      <td class="small">${esc(p.order_id ?? '—')}</td>
      <td>${p.revoked_at ? `<span class="badge red" title="${esc(p.revoke_reason)}">iade</span>` : '<span class="badge green">geçerli</span>'}</td>
      <td>${p.revoked_at ? '' : `<button class="btn small danger" data-revoke="${esc(p.id)}">İade et</button>`}</td></tr>`).join('')
      || `<tr><td colspan="${withUser ? 8 : 7}" class="muted">Satın alma yok.</td></tr>`}
    </tbody></table>`;
}

// İade butonları için tek dinleyici; sayfa değişince yalnızca geri çağrı değişir
let revokeAfter = null;
function bindRevoke(after) {
  revokeAfter = after;
}
function initRevoke() {
  view().addEventListener('click', async (e) => {
    const id = e.target.dataset?.revoke;
    if (!id) return;
    const reason = await ask({ title: 'Satın almayı iade et', danger: true, ok: 'İade et',
      text: 'Satın alma geçersiz sayılır ve verilen haklar kullanıcının bakiyesinden düşülür. Parayı Google Play Console\'dan ayrıca iade etmelisin.',
      input: { label: 'Gerekçe', placeholder: 'ör. kullanıcı iade istedi' } });
    if (!reason) return;
    try {
      const r = await api('POST', `/purchases/${id}/revoke`, { reason });
      toast(`İade edildi · kalan bakiye ${fmt(r.bonus)}`);
      revokeAfter?.();
    } catch (err) { toast(err.message, true); }
  });
}

const purchaseState = { page: 0, platform: 'all' };
async function purchases() {
  view().innerHTML = `<h1>Satın almalar</h1>
    <div class="panel">
      <div class="row"><select id="platform">
        ${[['all', 'Tüm kanallar'], ['google', 'Google Play'], ['test', 'Test']].map(([v, l]) =>
          `<option value="${v}" ${purchaseState.platform === v ? 'selected' : ''}>${l}</option>`).join('')}
      </select></div>
      <div class="table-wrap" id="purchase-table"></div>
    </div>`;
  $('#platform').addEventListener('change', (e) => { Object.assign(purchaseState, { platform: e.target.value, page: 0 }); loadPurchases(); });
  bindRevoke(loadPurchases);
  await loadPurchases();
}

async function loadPurchases() {
  const r = await api('GET', `/purchases?page=${purchaseState.page}&platform=${purchaseState.platform}`);
  const box = $('#purchase-table');
  box.innerHTML = purchaseTable(r.purchases);
  box.append(pager(r.total, r.page, r.pageSize, (p) => { purchaseState.page = p; loadPurchases(); }));
}

// ---------- paketler ----------
async function products() {
  const list = await api('GET', '/products');
  view().innerHTML = `<h1>Paketler</h1>
    <div class="panel">
      <p class="note">Kimlik, Google Play Console'daki ürün kimliğiyle birebir aynı olmalı. Fiyatı Play Console belirler.
        Pasif paket uygulamada görünmez; daha önce satın alınmışsa yine geçerlidir.</p>
      <div class="table-wrap"><table><thead><tr><th>Ürün kimliği</th><th>Hak</th><th>Sıra</th><th>Durum</th>
        <th class="num">Satılan</th><th></th></tr></thead><tbody id="products">
        ${list.map((p) => `<tr data-id="${esc(p.id)}"><td><b>${esc(p.id)}</b></td>
          <td><input type="number" min="1" name="credits" value="${p.credits}"></td>
          <td><input type="number" min="0" name="sort" value="${p.sort}"></td>
          <td><select name="active"><option value="true" ${p.active ? 'selected' : ''}>Satışta</option>
            <option value="false" ${p.active ? '' : 'selected'}>Pasif</option></select></td>
          <td class="num">${fmt(p.sold)}</td>
          <td><button class="btn small primary" data-save="1">Kaydet</button></td></tr>`).join('')}
      </tbody></table></div>
    </div>
    <div class="panel"><h2>Yeni paket</h2>
      <form class="row" id="product-form">
        <input name="id" placeholder="ör. tosso_hak_100" required pattern="[a-z0-9_.]{3,60}">
        <input name="credits" type="number" min="1" placeholder="hak sayısı" required>
        <button class="btn primary">Ekle</button>
      </form></div>`;
  $('#products').addEventListener('click', async (e) => {
    if (!e.target.dataset?.save) return;
    const tr = e.target.closest('tr');
    try {
      await api('PUT', `/products/${encodeURIComponent(tr.dataset.id)}`, {
        credits: Number(tr.querySelector('[name=credits]').value),
        sort: Number(tr.querySelector('[name=sort]').value),
        active: tr.querySelector('[name=active]').value === 'true',
      });
      toast('Paket kaydedildi');
    } catch (err) { toast(err.message, true); }
  });
  $('#product-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      await api('POST', '/products', { id: f.get('id').trim(), credits: Number(f.get('credits')) });
      toast('Paket eklendi');
      products();
    } catch (err) { toast(err.message, true); }
  });
}

// ---------- ayarlar ----------
async function settings() {
  const s = await api('GET', '/settings');
  view().innerHTML = `<h1>Ayarlar</h1>
    <div class="panel">
      <form id="settings-form" class="row">
        <label>Günlük ücretsiz mektup hakkı<input name="dailyFree" type="number" min="0" max="20" value="${s.dailyFree}"></label>
        <button class="btn primary">Kaydet</button>
      </form>
      <p class="note">Herkes için geçerlidir ve hemen uygulanır; Türkiye saatiyle gece yarısı yenilenir.
        Gelen her mektuba 1 cevap her zaman ücretsizdir.</p>
    </div>`;
  $('#settings-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const r = await api('PUT', '/settings', { dailyFree: Number(new FormData(e.target).get('dailyFree')) });
      toast(`Günlük ücretsiz hak: ${r.dailyFree}`);
    } catch (err) { toast(err.message, true); }
  });
}

// ---------- işlem kaydı ----------
function detailText(d) {
  if (!d) return '';
  return Object.entries(d).map(([k, v]) => `${esc(k)}: ${esc(typeof v === 'object' ? JSON.stringify(v) : v)}`).join(' · ');
}
function logTable(rows, withTarget = false) {
  return `<div class="table-wrap"><table><thead><tr><th>Tarih</th><th>Admin</th><th>İşlem</th>
    ${withTarget ? '<th>Kullanıcı</th>' : ''}<th>Ayrıntı</th></tr></thead><tbody>
    ${rows.map((g) => `<tr><td>${dt(g.created_at)}</td><td>${esc(g.admin ?? '—')}</td>
      <td>${esc(ACTIONS[g.action] ?? g.action)}</td>${withTarget ? `<td>${esc(g.target ?? '—')}</td>` : ''}
      <td class="small">${detailText(g.details)}</td></tr>`).join('')
      || `<tr><td colspan="${withTarget ? 5 : 4}" class="muted">Kayıt yok.</td></tr>`}
    </tbody></table></div>`;
}
const logState = { page: 0 };
async function logPage() {
  const r = await api('GET', `/log?page=${logState.page}`);
  view().innerHTML = `<h1>İşlem kaydı</h1><div class="panel" id="log-box">${logTable(r.entries, true)}</div>`;
  $('#log-box').append(pager(r.total, r.page, r.pageSize, (p) => { logState.page = p; logPage(); }));
}

// ---------- başlangıç ----------
async function start() {
  try {
    const me = await api('GET', '/me');
    $('#me').textContent = `@${me.username}`;
    $('#login').hidden = true;
    $('#app').hidden = false;
    route();
  } catch {
    logout();
  }
}

$('#login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  $('#login-error').hidden = true;
  try {
    const r = await api('POST', '/login', { username: f.get('username'), password: f.get('password') });
    token = r.token;
    sessionStorage.setItem('tosso_admin', token);
    start();
  } catch (err) {
    $('#login-error').textContent = err.message;
    $('#login-error').hidden = false;
  }
});
$('#logout').addEventListener('click', logout);
initRevoke();
window.addEventListener('hashchange', route);
if (token) start(); else logout();
