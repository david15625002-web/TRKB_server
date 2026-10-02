/* ==========================================================================
   TRKB prototype · view logic
   Vanilla JS, no build step, no dependencies. This is a DESIGN prototype:
   state lives in memory and resets on reload. Nothing here is production code.
   ========================================================================== */

const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = s => String(s).replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const ICON = {
  beranda:  '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/>',
  jadwal:   '<rect x="3" y="4.5" width="18" height="16" rx="2"/><path d="M8 2.5v4M16 2.5v4M3 10h18"/>',
  tugas:    '<path d="M9 4.5h6M8 4.5H6.5A1.5 1.5 0 0 0 5 6v13.5A1.5 1.5 0 0 0 6.5 21h11a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H16"/><path d="M8.5 12.5l2 2 4-4.5"/>',
  obrolan:  '<path d="M21 12a8 8 0 0 1-11.6 7.1L3 21l1.9-6.4A8 8 0 1 1 21 12z"/>',
  profil:   '<circle cx="12" cy="8" r="3.6"/><path d="M4.5 20.5a7.5 7.5 0 0 1 15 0"/>',
  organisasi:'<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="2.5" y="15.5" width="6" height="5" rx="1"/><rect x="15.5" y="15.5" width="6" height="5" rx="1"/><path d="M12 8v4M5.5 15.5v-2h13v2"/>',
  bell:     '<path d="M6.5 9.5a5.5 5.5 0 0 1 11 0c0 5 2 6.5 2 6.5H4.5s2-1.5 2-6.5z"/><path d="M10 19.5a2 2 0 0 0 4 0"/>',
  tema:     '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2.5 12h2M19.5 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/>',
  sparkle:  '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/>',
  plus:     '<path d="M12 5v14M5 12h14"/>',
  check:    '<path d="M4.5 12.5l5 5 10-11"/>',
  x:        '<path d="M6 6l12 12M18 6L6 18"/>',
  cari:     '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.3-4.3"/>',
};
const svg = (n, s = 19) =>
  `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor"
     stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON[n] || ''}</svg>`;

/* ---------- state -------------------------------------------------------- */

const S = {
  laman: 'beranda',
  hari: new Date().getDay() === 0 || new Date().getDay() === 6 ? 0 : new Date().getDay() - 1,
  ruang: 'r1',
  seed: 'green',
  mode: (typeof matchMedia === 'function'
         && matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light',
  gerak: true,
  tugasState: {},
  pesanTambahan: {},
};
DATA.tugas.forEach(t => (S.tugasState[t.id] = t.state));

/* ---------- helpers ------------------------------------------------------ */

function salam() {
  const h = new Date().getHours();
  if (h < 11) return 'Selamat pagi';
  if (h < 15) return 'Selamat siang';
  if (h < 18) return 'Selamat sore';
  return 'Selamat malam';
}
function jamKe(h) {
  if (h < 0) return 'lewat ' + fmtDur(-h);
  return fmtDur(h);
}
function fmtDur(h) {
  if (h < 1) return Math.round(h * 60) + ' menit';
  if (h < 24) return Math.floor(h) + ' jam';
  const d = Math.floor(h / 24), r = Math.floor(h % 24);
  return d + ' hari' + (r ? ' ' + r + ' jam' : '');
}
function tugasKelas(t) {
  const st = S.tugasState[t.id];
  if (st === 'done') return 'task done';
  if (t.jamLagi > 0 && t.jamLagi <= 6) return 'task urgent';
  return 'task';
}
function prioChip(p) {
  const m = { urgent: ['danger', 'Mendesak'], high: ['warn', 'Penting'], normal: ['', 'Biasa'], low: ['', 'Santai'] };
  const [c, l] = m[p] || ['', p];
  return `<span class="chip ${c}">${c ? '<i class="dotc"></i>' : ''}${l}</span>`;
}
function toast(judul, isi) {
  const box = $('#toasts');
  const el = document.createElement('div');
  el.className = 'toast';
  el.innerHTML = `<div class="ti">${svg('bell', 17)}</div>
    <div style="min-width:0"><div class="tl">${esc(judul)}</div><div class="tb">${esc(isi)}</div></div>`;
  box.appendChild(el);
  setTimeout(() => { el.style.transition = 'opacity .3s'; el.style.opacity = '0'; setTimeout(() => el.remove(), 320); }, 4200);
}

/* ---------- countdown to the next class --------------------------------- */

function nextClass() {
  const now = new Date();
  const hariIni = now.getDay() === 0 || now.getDay() === 6 ? 0 : now.getDay() - 1;
  const menitSekarang = now.getHours() * 60 + now.getMinutes();
  const kandidat = DATA.jadwal
    .filter(j => j.status !== 'cancelled')
    .map(j => {
      const [h, m] = j.mulai.split(':').map(Number);
      let delta = (j.hari - hariIni) * 1440 + (h * 60 + m) - menitSekarang;
      if (delta < 0) delta += 7 * 1440;
      return { ...j, delta };
    })
    .sort((a, b) => a.delta - b.delta);
  return kandidat[0];
}
function tickCountdown() {
  const el = $('#cd');
  if (!el) return;
  const n = nextClass();
  const total = n.delta * 60 - new Date().getSeconds();
  const j = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  el.textContent = j > 24
    ? `${Math.floor(j / 24)}h ${j % 24}j`
    : `${String(j).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

/* ---------- pages ------------------------------------------------------- */

function pBeranda() {
  const n = nextClass();
  const hariIni = DATA.jadwal.filter(j => j.hari === S.hari);
  const aktif = DATA.tugas.filter(t => S.tugasState[t.id] !== 'done').sort((a, b) => a.jamLagi - b.jamLagi);
  const st = DATA.me.stats;

  return `
  <div class="hero">
    <div class="eyebrow">${esc(DATA.term.nama)} · pekan ${DATA.term.pekan} dari ${DATA.term.totalPekan}</div>
    <h1>${salam()}, ${esc(DATA.me.display.split(' ')[0])} 👋</h1>
    <div class="sub">${esc(DATA.me.kelas)} · Semester ${DATA.me.semester} · ${esc(DATA.me.peran)}</div>
  </div>

  <div class="stack">
    <div class="next enter">
      <div style="min-width:0">
        <div style="font-size:13px;opacity:.85;margin-bottom:2px">Kelas berikutnya</div>
        <div class="ttl">${esc(n.mk)}</div>
        <div style="font-size:13.5px;opacity:.85;margin-top:3px">
          ${esc(n.mulai)}–${esc(n.selesai)} · ${esc(n.ruang)}
        </div>
      </div>
      <div class="spacer"></div>
      <div style="text-align:right">
        <div class="cd" id="cd">--:--:--</div>
        <div style="font-size:12.5px;opacity:.85">lagi</div>
      </div>
    </div>

    <div class="streakbar enter">
      <span class="fire">🔥</span>
      <div style="min-width:0;flex:1">
        <div class="n">${st.streak} hari beruntun!</div>
        <div class="bar" style="margin-top:7px"><i style="width:${Math.min(100, st.streak / 30 * 100)}%"></i></div>
      </div>
      <div class="note" style="font-weight:800">30</div>
    </div>

    <div class="metrics enter">
      <div class="metric"><div class="n" style="color:var(--accent-text)">${aktif.length}</div><div class="t">Tugas aktif</div></div>
      <div class="metric"><div class="n" style="color:var(--success-text)">${st.tepat}</div><div class="t">Tepat waktu</div></div>
      <div class="metric"><div class="n" style="color:var(--streak)">${st.streak}</div><div class="t">Hari beruntun</div></div>
      <div class="metric"><div class="n">${hariIni.length}</div><div class="t">Kelas hari ini</div></div>
    </div>

    <div class="grid2">
      <section class="panel enter">
        <header>
          <h2>Jadwal ${esc(DATA.hari[S.hari])}</h2>
          <div class="spacer"></div>
          <button class="btn sm ghost" data-go="jadwal">Semua</button>
        </header>
        <div class="body">
          ${hariIni.length ? `<div class="agenda">${hariIni.map(slotHTML).join('')}</div>`
            : `<div class="empty"><div class="ico">${svg('jadwal', 24)}</div>Tidak ada kelas hari ini. Nikmati waktunya.</div>`}
        </div>
      </section>

      <section class="panel enter">
        <header>
          <h2>Tenggat terdekat</h2>
          <div class="spacer"></div>
          <button class="btn sm ghost" data-go="tugas">Semua</button>
        </header>
        <div class="body">
          <div class="stack" style="gap:8px">
            ${aktif.slice(0, 3).map(taskHTML).join('') ||
              `<div class="empty"><div class="ico">${svg('check', 24)}</div>Tidak ada tugas aktif. Mantap.</div>`}
          </div>
        </div>
      </section>
    </div>

    ${DATA.menunggu.length ? `
    <section class="panel enter" style="border-color:var(--warn-text)">
      <header>
        <span class="led warn"><i></i></span>
        <h2>Menunggu persetujuanmu</h2>
        <div class="spacer"></div>
        <span class="chip warn">${DATA.menunggu.length}</span>
      </header>
      <div class="body"><div class="stack" style="gap:8px">
        ${DATA.menunggu.map(m => `
          <div class="node">
            <div class="avatar sm">${esc(m.inisial)}</div>
            <div class="who"><div class="nm">${esc(m.nama)}</div>
              <div class="rl">${esc(m.nim)} · ${esc(m.kelas)} · ${esc(m.kapan)}</div></div>
            <button class="btn sm primary" data-act="setuju" data-n="${esc(m.nama)}">Setujui</button>
            <button class="btn sm ghost" data-act="tolak" data-n="${esc(m.nama)}">Tolak</button>
          </div>`).join('')}
      </div></div>
    </section>` : ''}
  </div>`;
}

function slotHTML(j) {
  const cls = j.status === 'cancelled' ? 'slot cancelled' : 'slot';
  // Each subject keeps the same colour everywhere, so the week reads at a glance.
  const warna = `var(--subj-${(DATA.jadwal.findIndex(x => x.kode === j.kode) % 6) + 1})`;
  return `<div class="${cls}" style="--subj:${warna}">
    <div class="time mono"><b>${esc(j.mulai)}</b>${esc(j.selesai)}</div>
    <div class="rail"></div>
    <div>
      <div class="nm">${esc(j.mk)}</div>
      <div class="note" style="margin-top:1px">${esc(j.ruang)} · ${esc(j.kode)}</div>
      <div class="meta">
        <span class="chip">${esc(j.jenis)}</span>
        ${j.status === 'cancelled' ? `<span class="chip danger"><i class="dotc"></i>Dibatalkan</span>` : ''}
        ${j.status === 'moved' ? `<span class="chip warn"><i class="dotc"></i>Dipindah</span>` : ''}
        ${j.catatan ? `<span class="chip">${esc(j.catatan)}</span>` : ''}
      </div>
    </div>
  </div>`;
}

function taskHTML(t) {
  const done = S.tugasState[t.id] === 'done';
  return `<div class="${tugasKelas(t)}">
    <button class="check" role="checkbox" aria-checked="${done}" data-act="toggle" data-id="${t.id}"
            aria-label="Tandai selesai">${svg('check', 13)}</button>
    <div style="flex:1;min-width:0">
      <div class="tt">${esc(t.judul)}</div>
      <div class="due">${esc(t.mk)} · ${done ? 'selesai' : jamKe(t.jamLagi) + ' lagi'} · ${esc(t.kanal)}</div>
      <div class="tmeta">
        ${prioChip(t.prioritas)}
        <span class="chip">${esc(t.jenis)}</span>
        ${t.jamLagi > 0 && t.jamLagi <= 6 && !done ? `<span class="chip danger">${Math.ceil(t.jamLagi)} jam lagi</span>` : ''}
        ${t.jamLagi < 0 && !done ? `<span class="chip danger">Terlambat</span>` : ''}
      </div>
    </div>
  </div>`;
}

function pJadwal() {
  return `
  <div class="hero">
    <h1>Jadwal</h1>
    <div class="sub">${esc(DATA.me.kelas)} · ${esc(DATA.term.nama)} · pekan ${DATA.term.pekan} dari ${DATA.term.totalPekan}</div>
  </div>

  <div class="daystrip">
    ${DATA.hari.map((h, i) => `
      <button class="daybtn" aria-pressed="${i === S.hari}" data-act="hari" data-i="${i}">
        ${h.slice(0, 3).toUpperCase()}<b>${DATA.jadwal.filter(j => j.hari === i).length}</b>
      </button>`).join('')}
  </div>

  <div class="stack">
    <section class="panel enter">
      <header><h2>${esc(DATA.hari[S.hari])}</h2>
        <div class="spacer"></div>
      </header>
      <div class="body">
        <div class="agenda">
          ${DATA.jadwal.filter(j => j.hari === S.hari).map(slotHTML).join('') ||
            `<div class="empty">Tidak ada kelas ${esc(DATA.hari[S.hari])}.</div>`}
        </div>
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Tampilan pekan</h2><div class="spacer"></div>
        <span class="note">gulir mendatar</span></header>
      <div class="body">
        <div class="weekwrap">${weekGrid()}</div>
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Impor jadwal</h2></header>
      <div class="body">
        <p class="note">Sekretaris menginput jadwal sekali per semester. Sistem membuat
        seluruh pertemuan mingguan secara otomatis, melewati pekan UTS, UAS, dan libur.</p>
        <div class="row" style="margin-top:10px">
          <button class="btn" data-act="demo">Unggah CSV / Excel</button>
          <button class="btn ghost" data-act="demo">Tempel dari papan klip</button>
        </div>
        <div class="sep"></div>
        <div class="drow"><span class="k">Bentrok terdeteksi</span><span class="v" style="color:var(--success-text)">0</span></div>
        <div class="drow"><span class="k">Pertemuan dibuat</span><span class="v">135</span></div>
        <div class="drow"><span class="k">Pekan dilewati</span><span class="v">UTS · Libur</span></div>
      </div>
    </section>
  </div>`;
}

function weekGrid() {
  let html = `<div class="week"><div class="hd"></div>${DATA.hari.map(h => `<div class="hd">${h.slice(0, 3)}</div>`).join('')}`;
  DATA.jamGrid.forEach(jam => {
    html += `<div class="hr mono">${jam}</div>`;
    DATA.hari.forEach((_, d) => {
      const j = DATA.jadwal.find(x => x.hari === d && x.mulai === jam);
      html += `<div class="cell">${j ? `
        <div class="wblock" style="${j.status === 'cancelled' ? 'opacity:.5;text-decoration:line-through' : ''}">
          <b>${esc(j.mk.length > 18 ? j.mk.slice(0, 17) + '…' : j.mk)}</b>
          <span>${esc(j.ruang)}</span>
        </div>` : ''}</div>`;
    });
  });
  return html + '</div>';
}

function pTugas() {
  const aktif = DATA.tugas.filter(t => S.tugasState[t.id] !== 'done').sort((a, b) => a.jamLagi - b.jamLagi);
  const selesai = DATA.tugas.filter(t => S.tugasState[t.id] === 'done');
  return `
  <div class="hero">
    <h1>Tugas</h1>
    <div class="sub">${aktif.length} aktif · ${selesai.length} selesai · ${esc(DATA.me.kelas)}</div>
  </div>

  <div class="stack">
    <section class="panel enter">
      <header><span class="led danger"><i></i></span><h2>Aktif</h2>
        <div class="spacer"></div><span class="chip">${aktif.length}</span></header>
      <div class="body"><div class="stack" style="gap:8px">
        ${aktif.map(taskHTML).join('') || `<div class="empty"><div class="ico">${svg('check', 24)}</div>Semua tugas selesai.</div>`}
      </div></div>
    </section>

    <section class="panel enter">
      <header><span class="led ok"><i></i></span><h2>Selesai</h2>
        <div class="spacer"></div><span class="chip ok">${selesai.length}</span></header>
      <div class="body"><div class="stack" style="gap:8px">
        ${selesai.map(taskHTML).join('') || `<div class="empty">Belum ada.</div>`}
      </div></div>
    </section>

    <section class="panel enter">
      <header><h2>Pengingat yang dijadwalkan</h2></header>
      <div class="body">
        <p class="note">Jadwal pengiriman yang dihasilkan sistem untuk
        <b>${esc(aktif[0] ? aktif[0].judul : '—')}</b>:</p>
        <div class="sep"></div>
        <div class="drow"><span class="k">H-1 · 18:00 WIB</span><span class="v">dalam aplikasi · push · email</span></div>
        <div class="drow"><span class="k">H-3 jam</span><span class="v">dalam aplikasi · push</span></div>
        <div class="drow"><span class="k">Jam tenang</span><span class="v">22:00–06:00 ditunda</span></div>
        <div class="drow"><span class="k">Kunci anti-ganda</span><span class="v" style="font-size:11px">task:…:1440:push</span></div>
      </div>
    </section>
  </div>`;
}

function pOrganisasi() {
  const o = DATA.organisasi;
  return `
  <div class="hero"><h1>Organisasi</h1><div class="sub">${esc(o.nama)}</div></div>

  <div class="stack">
    <section class="panel enter">
      <header><h2>Badan pengurus harian</h2><div class="spacer"></div>
        <span class="chip">Program</span></header>
      <div class="body"><div class="tree">
        ${o.bph.map((b, i) => `
          <div class="node ${i ? 'depth1 connector' : ''}">
            <div class="avatar sm">${esc(b.inisial)}</div>
            <div class="who"><div class="nm">${esc(b.orang)}</div>
              <div class="rl">${esc(b.nama).toUpperCase()} · ${esc(b.nim)}</div></div>
            <span class="chip accent">rank ${i === 0 ? 10 : 20}</span>
          </div>`).join('')}
      </div></div>
    </section>

    <section class="panel enter">
      <header><h2>Divisi</h2><div class="spacer"></div>
        <button class="btn sm ghost" data-act="demo">${svg('plus', 13)} Divisi baru</button></header>
      <div class="body"><div class="tree">
        ${o.divisi.map(d => `
          <div class="node">
            <div class="avatar sm">${esc(d.inisial)}</div>
            <div class="who"><div class="nm">${esc(d.nama)}</div>
              <div class="rl">KADIV ${esc(d.kadiv).toUpperCase()} · ${d.anggota} anggota</div></div>
            <span class="chip">rank 30</span>
          </div>`).join('')}
      </div>
      <p class="note" style="margin-top:11px">Struktur divisi dapat ditambah atau dihapus
      Super Admin tanpa perubahan basis data.</p>
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Kelas</h2><div class="spacer"></div>
        <span class="note">semester dihitung dari angkatan</span></header>
      <div class="body flush">
        ${o.kelas.map(k => `
          <div class="room" style="cursor:default">
            <div class="avatar sm mono" style="font-size:9.5px">${esc(k.kode.split(' ')[1])}</div>
            <div style="min-width:0;flex:1">
              <div class="rn">${esc(k.kode)} <span class="chip accent">Sem ${k.semester}</span></div>
              <div class="rp">Ketua ${esc(k.ketua)} · Sekretaris ${esc(k.sekretaris)} · ${k.anggota} anggota</div>
            </div>
            ${k.pending ? `<span class="chip warn">${k.pending} menunggu</span>` : `<span class="led ok"><i></i>lengkap</span>`}
          </div>`).join('')}
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Cakupan izin</h2></header>
      <div class="body">
        <p class="note">Peran diberikan <b>pada sebuah unit</b> dan berlaku untuk unit itu
        beserta seluruh turunannya.</p>
        <div class="sep"></div>
        <div class="drow"><span class="k">Ketua HIMA → semua kelas</span><span class="v" style="color:var(--success-text)">diizinkan</span></div>
        <div class="drow"><span class="k">Ketua Kelas TRKB-1 25 → TRKB-1 25</span><span class="v" style="color:var(--success-text)">diizinkan</span></div>
        <div class="drow"><span class="k">Ketua Kelas TRKB-1 25 → TRKB-2 25</span><span class="v" style="color:var(--danger-text)">ditolak</span></div>
        <div class="drow"><span class="k">Anggota → membuat tugas</span><span class="v" style="color:var(--danger-text)">ditolak</span></div>
      </div>
    </section>
  </div>`;
}

function pObrolan() {
  const r = DATA.ruang.find(x => x.id === S.ruang);
  const ps = [...(DATA.pesan[S.ruang] || []), ...(S.pesanTambahan[S.ruang] || [])];
  return `
  <div class="hero"><h1>Obrolan</h1>
    <div class="sub">Ruang kelas dan divisi dibuat otomatis.</div></div>
  <div class="chatwrap">
    <section class="panel enter">
      <header><h2>Ruang</h2><div class="spacer"></div>
        <button class="iconbtn" data-act="demo" aria-label="Cari">${svg('cari', 16)}</button></header>
      <div class="body flush">
        ${DATA.ruang.map(x => `
          <div class="room" aria-selected="${x.id === S.ruang}" data-act="ruang" data-id="${x.id}">
            <div class="avatar sm" style="font-size:14px">${x.ikon}</div>
            <div style="min-width:0;flex:1">
              <div class="rn">${esc(x.nama)}</div>
              <div class="rp">${esc(x.terakhir)}</div>
            </div>
            ${x.belum ? `<div class="badge mono">${x.belum}</div>` : ''}
          </div>`).join('')}
      </div>
    </section>

    <section class="panel enter">
      <header>
        <div class="avatar sm" style="font-size:14px">${r.ikon}</div>
        <div><div style="font-weight:600;font-size:14px">${esc(r.nama)}</div>
          <div class="label">${r.jenis === 'dm' ? 'pesan pribadi' : r.jenis === 'announcement' ? 'kanal pengumuman · hanya pengurus' : r.jenis}</div></div>
        <div class="spacer"></div>
        <span class="led live"><i></i>realtime</span>
      </header>

      ${r.jenis === 'dm' ? `
      <div class="privacy">
        <span>${svg('bell', 15)}</span>
        <div><b>Pesan tidak terenkripsi ujung-ke-ujung.</b> Super Admin memiliki akses
        basis data dan secara teknis dapat membacanya. Jangan kirim hal yang sangat pribadi.</div>
      </div>` : ''}

      <div class="msgs" id="msgs">
        ${ps.map(m => m.sys
          ? `<div class="msg system"><div class="bubble">${esc(m.isi)}</div></div>`
          : `<div class="msg ${m.me ? 'me' : ''}">
               <div class="avatar sm">${esc(m.inisial)}</div>
               <div class="bubble">
                 <div class="mh"><span class="mn">${esc(m.nama)}</span>
                   <span class="mt mono">${esc(m.peran)} · ${esc(m.jam)}</span></div>
                 <div class="mb">${esc(m.isi)}</div>
               </div>
             </div>`).join('')}
      </div>

      ${r.jenis === 'announcement' ? `
        <div class="composer"><div class="note" style="padding:8px">
          Kanal hanya-baca. Hanya pemegang izin <span class="mono">announcement.post</span> dapat mengirim.
        </div></div>`
      : `<form class="composer" data-act="kirim">
          <input id="msgin" placeholder="Tulis pesan…" autocomplete="off" aria-label="Pesan">
          <button class="btn primary" type="submit">Kirim</button>
         </form>`}
    </section>
  </div>`;
}

function pProfil() {
  const m = DATA.me, st = m.stats;
  const pct = Math.round((st.tepat / (st.tepat + st.telat)) * 100);
  return `
  <div class="stack">
    <section class="panel enter" style="overflow:hidden">
      <div class="banner"></div>
      <div class="phead">
        <div class="avatar lg ring">${esc(m.inisial)}</div>
        <div style="flex:1;min-width:0;padding-bottom:6px">
          <h2>${esc(m.display)}</h2>
          <div class="mono" style="font-size:12px;color:var(--muted)">
            ${esc(m.nim)} · ${esc(m.kelas)} · Semester ${m.semester}
          </div>
        </div>
        <button class="btn sm ghost" style="margin-bottom:6px" data-act="demo">Edit</button>
      </div>
      <div class="body">
        <div style="font-weight:500;margin-bottom:4px">${esc(m.headline)}</div>
        <p class="note">${esc(m.bio)}</p>
        <div class="row" style="margin-top:10px">
          <span class="chip accent">${esc(m.peran)}</span>
          <span class="chip">Anggota Divisi Ristek</span>
          <span class="chip">kata ganti: ${esc(m.pronouns)}</span>
        </div>
      </div>
    </section>

    <div class="grid2">
      <section class="panel enter">
        <header><h2>Statistik</h2></header>
        <div class="body">
          <div class="row" style="justify-content:space-between;margin-bottom:6px">
            <span class="note">Ketepatan waktu</span><span class="mono" style="color:var(--success-text)">${pct}%</span>
          </div>
          <div class="bar"><i style="width:${pct}%"></i></div>
          <div class="sep"></div>
          <div class="drow"><span class="k">Tugas selesai</span><span class="v">${st.selesai}</span></div>
          <div class="drow"><span class="k">Tepat waktu</span><span class="v" style="color:var(--success-text)">${st.tepat}</span></div>
          <div class="drow"><span class="k">Terlambat</span><span class="v" style="color:var(--danger-text)">${st.telat}</span></div>
          <div class="drow"><span class="k">Runtun saat ini</span><span class="v" style="color:var(--warn-text)">${st.streak} hari</span></div>
          <div class="drow"><span class="k">Runtun terbaik</span><span class="v">${st.streakBest} hari</span></div>
          <p class="note" style="margin-top:10px">Tidak ada papan peringkat publik — angka ini hanya milikmu.</p>
        </div>
      </section>

      <section class="panel enter">
        <header><h2>Lencana</h2><div class="spacer"></div>
          <span class="chip">${DATA.lencana.filter(b => b.punya).length}/${DATA.lencana.length}</span></header>
        <div class="body">
          <div class="badgeshelf">
            ${DATA.lencana.map(b => `
              <div class="bdg ${b.punya ? b.t : 'locked'}">
                <div class="ic">${b.ic}</div><div class="bn">${esc(b.n)}</div>
              </div>`).join('')}
          </div>
        </div>
      </section>
    </div>

    <section class="panel enter">
      <header><h2>Keahlian</h2><div class="spacer"></div>
        <button class="btn sm ghost" data-act="demo">${svg('plus', 13)} Tambah</button></header>
      <div class="body">
        <div class="cloud">
          ${DATA.keahlian.map(k => `
            <span class="chip ${k.lv === 3 ? 'accent' : ''}">${esc(k.n)}
              <b class="mono" style="opacity:.7">${'•'.repeat(k.lv)}</b></span>`).join('')}
        </div>
        <p class="note" style="margin-top:10px">Tiga tingkat: belajar · bisa · mahir.
        Daftar dikurasi agar tidak muncul sepuluh ejaan untuk satu keahlian.</p>
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Portofolio</h2><div class="spacer"></div>
        <button class="btn sm ghost" data-act="demo">${svg('plus', 13)} Proyek</button></header>
      <div class="body">
        <div class="stack" style="gap:12px">
          ${DATA.proyek.map(p => `
            <div class="proj">
              <div class="cv">${esc(p.judul)}</div>
              <div class="pb">
                <div style="font-weight:600">${esc(p.judul)}</div>
                <div class="mono" style="font-size:11px;color:var(--muted);margin:2px 0 6px">
                  ${esc(p.konteks)} · ${p.tahun} · ${p.tim} orang</div>
                <p class="note">${esc(p.ringkas)}</p>
                <div class="row" style="margin-top:8px">
                  ${p.tag.map(t => `<span class="chip">${esc(t)}</span>`).join('')}
                </div>
              </div>
            </div>`).join('')}
        </div>
      </div>
    </section>
  </div>`;
}

function pPengaturan() {
  return `
  <div class="hero"><h1>Pengaturan</h1>
    <div class="sub">Pilihan ini tersimpan di profilmu, jadi ikut ke perangkat lain.</div></div>
  <div class="stack">
    <section class="panel enter">
      <header><h2>Warna aksen</h2></header>
      <div class="body">
        <p class="note" style="margin-bottom:14px">Pilih satu warna. Seluruh aplikasi mengikutinya.</p>
        <div class="seeds">
          ${DATA.seeds.map(w => `
            <button class="seedbtn" aria-pressed="${S.seed === w.id}"
                    data-act="seed" data-id="${w.id}" aria-label="${esc(w.nama)}"
                    style="background:${w.hex};color:${w.ink};box-shadow:0 4px 0 ${w.deep};border-color:${w.deep}">
              ${svg('check', 22)}
            </button>`).join('')}
        </div>
        <p class="note" style="margin-top:10px">${DATA.seeds.find(w => w.id === S.seed).nama}</p>
        <div class="sep"></div>
        <div class="switchrow">
          <div><div style="font-weight:600">Tampilan</div>
            <div class="note">Terang, gelap, atau ikuti perangkat</div></div>
          <div class="segmented">
            ${[['light','Terang'],['dark','Gelap'],['system','Sistem']].map(([v,l]) => `
              <button aria-pressed="${S.mode === v}" data-act="mode" data-m="${v}">${l}</button>`).join('')}
          </div>
        </div>
        <div class="switchrow">
          <div><div style="font-weight:600">Animasi</div>
            <div class="note">Kurangi gerakan bila membuat tidak nyaman</div></div>
          <div class="segmented">
            <button aria-pressed="${S.gerak}" data-act="gerak" data-g="1">Aktif</button>
            <button aria-pressed="${!S.gerak}" data-act="gerak" data-g="0">Kurangi</button>
          </div>
        </div>
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Pengingat</h2></header>
      <div class="body">
        <div class="fieldset">
          <label><span class="label">Pengingat tugas</span>
            <select class="field"><option>H-1 (18:00) dan H-3 jam — bawaan</option>
              <option>Hanya H-1</option><option>H-7, H-1, H-3 jam</option></select></label>
          <label><span class="label">Pengingat kelas</span>
            <select class="field"><option>30 menit sebelum — bawaan</option>
              <option>15 menit</option><option>1 jam</option><option>Nonaktif</option></select></label>
          <label><span class="label">Jam tenang</span>
            <select class="field"><option>22:00 – 06:00 (ditunda, bukan dibatalkan)</option>
              <option>Tidak ada</option></select></label>
        </div>
        <div class="sep"></div>
        <div class="drow"><span class="k">Dalam aplikasi</span><span class="v" style="color:var(--success-text)">Aktif</span></div>
        <div class="drow"><span class="k">Push ke ponsel</span><span class="v" style="color:var(--success-text)">Aktif</span></div>
        <div class="drow"><span class="k">Email</span><span class="v">Ringkasan harian</span></div>
        <p class="note" style="margin-top:12px">Email dibatasi ringkasan harian karena kuota gratis
        3.000 kiriman per bulan tidak cukup untuk notifikasi per kejadian.</p>
      </div>
    </section>

    <section class="panel enter">
      <header><h2>Coba notifikasi</h2></header>
      <div class="body">
        <div class="row">
          <button class="btn tonal" data-act="notifDemo" data-k="h1">H-1</button>
          <button class="btn tonal" data-act="notifDemo" data-k="h3">H-3 jam</button>
          <button class="btn tonal" data-act="notifDemo" data-k="kelas">Kelas mulai</button>
          <button class="btn tonal" data-act="notifDemo" data-k="batal">Kelas batal</button>
        </div>
      </div>
    </section>
  </div>`;
}

function pNotifikasi() {
  return `
  <div class="hero"><h1>Notifikasi</h1>
    <div class="sub">${DATA.notifikasi.filter(n => n.baru).length} belum dibaca</div></div>
  <section class="panel enter">
    <header><h2>Kotak masuk</h2><div class="spacer"></div>
      <button class="btn sm ghost" data-act="demo">Tandai semua dibaca</button></header>
    <div class="body flush">
      ${DATA.notifikasi.map(n => `
        <div class="room" style="cursor:default;${n.baru ? 'background:var(--accent-soft)' : ''}">
          <div class="avatar sm" style="font-size:15px">${n.ic}</div>
          <div style="min-width:0;flex:1">
            <div class="rn">${esc(n.j)}</div>
            <div class="rp">${esc(n.b)}</div>
          </div>
          <div style="text-align:right">
            <div class="mono" style="font-size:10.5px;color:var(--muted)">${esc(n.w)}</div>
            ${n.baru ? `<span class="led live" style="justify-content:flex-end"><i></i></span>` : ''}
          </div>
        </div>`).join('')}
    </div>
  </section>`;
}

const PAGES = {
  beranda: pBeranda, jadwal: pJadwal, tugas: pTugas, organisasi: pOrganisasi,
  obrolan: pObrolan, profil: pProfil, pengaturan: pPengaturan, notifikasi: pNotifikasi,
};
const NAV = [
  ['beranda', 'Beranda'], ['jadwal', 'Jadwal'], ['tugas', 'Tugas'],
  ['obrolan', 'Obrolan'], ['organisasi', 'Organisasi'], ['profil', 'Profil'],
];
const TABS = [['beranda', 'Beranda'], ['jadwal', 'Jadwal'], ['tugas', 'Tugas'], ['obrolan', 'Chat'], ['profil', 'Profil']];

/* ---------- render ------------------------------------------------------ */

function render() {
  $('#sidenav').innerHTML = NAV.map(([k, l]) => `
    <button class="navlink" data-go="${k}" ${S.laman === k ? 'aria-current="page"' : ''}>
      ${svg(k)} <span>${l}</span>
    </button>`).join('') + `
    <div class="sep"></div>
    <button class="navlink" data-go="pengaturan" ${S.laman === 'pengaturan' ? 'aria-current="page"' : ''}>
      ${svg('tema')} <span>Pengaturan</span></button>`;

  $('#tabbar').innerHTML = TABS.map(([k, l]) => `
    <button class="tab" data-go="${k}" ${S.laman === k ? 'aria-current="page"' : ''}>
      <span class="pill">${svg(k, 21)}</span><span>${l}</span></button>`).join('');

  $('#view').innerHTML = (PAGES[S.laman] || pBeranda)();

  // One floating primary action, only where there is an obvious one.
  const FAB = { tugas: ['tambahTugas', 'Tugas baru'], jadwal: ['tambahJadwal', 'Tambah slot'] }[S.laman];
  $('#fab').innerHTML = FAB
    ? `<button class="fab" data-act="${FAB[0]}">${svg('plus', 21)} <span>${FAB[1]}</span></button>`
    : '';
  $$('.enter').forEach((el, i) => (el.style.animationDelay = i * 40 + 'ms'));
  tickCountdown();
  const m = $('#msgs'); if (m) m.scrollTop = m.scrollHeight;
}

function applyTheme() {
  const r = document.documentElement;
  r.setAttribute('data-accent', S.seed);
  // 'system' resolves now, so the tokens only ever see 'light' or 'dark'.
  const mode = S.mode === 'system'
    ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    : S.mode;
  r.setAttribute('data-mode', mode);
  r.setAttribute('data-motion', S.gerak ? 'on' : 'off');
}

/* ---------- events ------------------------------------------------------ */

document.addEventListener('click', e => {
  const go = e.target.closest('[data-go]');
  if (go) { S.laman = go.dataset.go; render(); window.scrollTo({ top: 0, behavior: 'smooth' }); return; }

  const a = e.target.closest('[data-act]');
  if (!a) return;
  const act = a.dataset.act;

  if (act === 'hari')   { S.hari = +a.dataset.i; render(); }
  if (act === 'ruang')  { S.ruang = a.dataset.id; render(); }
  if (act === 'seed')   { S.seed = a.dataset.id; applyTheme(); render(); }
  if (act === 'mode')   { S.mode = a.dataset.m; applyTheme(); render(); }
  if (act === 'gerak')  { S.gerak = a.dataset.g === '1'; applyTheme(); render(); }

  if (act === 'toggle') {
    const id = a.dataset.id;
    const now = S.tugasState[id] === 'done' ? 'todo' : 'done';
    S.tugasState[id] = now;
    const t = DATA.tugas.find(x => x.id === id);
    render();
    if (now === 'done') toast('Ditandai selesai', `${t.judul} · ${t.jamLagi > 0 ? 'tepat waktu' : 'terlambat'}`);
  }

  if (act === 'setuju') { toast('Anggota disetujui', `${a.dataset.n} masuk ke ${DATA.me.kelas} dan ruang obrolan kelas.`); a.closest('.node').remove(); }
  if (act === 'tolak')  { toast('Permintaan ditolak', `${a.dataset.n} tidak ditambahkan.`); a.closest('.node').remove(); }

  if (act === 'tambahTugas')  openModal('tugas');
  if (act === 'tambahJadwal') openModal('jadwal');
  if (act === 'demo') toast('Prototipe', 'Alur ini ada di rancangan, belum diimplementasikan.');

  if (act === 'notifDemo') {
    const k = a.dataset.k;
    const p = {
      h1:    ['Besok: Laporan Praktikum Mikrokontroler', 'Mikrokontroler · dikumpulkan 23:59'],
      h3:    ['Segera: Laporan Praktikum Mikrokontroler', 'Mikrokontroler · dikumpulkan 23:59'],
      kelas: ['Mikrokontroler · 30 menit lagi', 'Ruang Lab Robotika 1'],
      batal: ['Kelas dibatalkan', 'Metodologi Penelitian · Dosen tugas ke luar kota'],
    }[k];
    toast(p[0], p[1]);
  }

  if (act === 'tutup') closeModal();
});

document.addEventListener('submit', e => {
  const f = e.target.closest('[data-act="kirim"]');
  if (f) {
    e.preventDefault();
    const inp = $('#msgin');
    const v = inp.value.trim();
    if (!v) return;
    (S.pesanTambahan[S.ruang] = S.pesanTambahan[S.ruang] || []).push({
      me: true, nama: DATA.me.display, peran: DATA.me.peran, inisial: DATA.me.inisial,
      jam: new Date().toTimeString().slice(0, 5), isi: v,
    });
    render();
    return;
  }
  const m = e.target.closest('#modalform');
  if (m) {
    e.preventDefault();
    const judul = $('#f_judul').value.trim() || 'Tugas baru';
    closeModal();
    toast('Tugas dipublikasikan', `${judul} · pengingat H-1 dan H-3 jam dijadwalkan untuk 38 anggota`);
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeModal();
  if (e.key === 'Enter' || e.key === ' ') {
    const l = e.target.closest('.navlink[data-go]');
    if (l) { e.preventDefault(); l.click(); }
  }
});

/* ---------- modal ------------------------------------------------------- */

function openModal(kind) {
  const body = kind === 'tugas' ? `
    <div class="fieldset">
      <label><span class="label">Judul tugas</span>
        <input class="field" id="f_judul" placeholder="Laporan Praktikum Pekan 5"></label>
      <label><span class="label">Mata kuliah</span>
        <select class="field">${DATA.jadwal.map(j => `<option>${esc(j.mk)}</option>`).join('')}</select></label>
      <label><span class="label">Jenis</span>
        <select class="field"><option>tugas</option><option>quiz</option><option>ujian</option>
          <option>praktikum</option><option>proyek</option><option>presentasi</option></select></label>
      <label><span class="label">Tenggat</span><input class="field" type="datetime-local"></label>
      <label><span class="label">Kanal pengumpulan</span>
        <select class="field"><option>Kumpulkan di kelas</option><option>LMS UNIKOM</option>
          <option>Email dosen</option><option>Google Drive</option></select></label>
      <label><span class="label">Keterangan</span><input class="field" placeholder="Opsional"></label>
    </div>
    <div class="privacy" style="margin:16px 0 0;background:var(--accent-soft);color:var(--accent-text)">
      <div>Menerbitkan akan menjadwalkan pengingat <b>H-1 pukul 18:00</b> dan
      <b>H-3 jam</b> untuk 38 anggota ${esc(DATA.me.kelas)}, menghormati bisu per mata
      kuliah dan jam tenang masing-masing.</div>
    </div>` : `
    <div class="fieldset">
      <label><span class="label">Mata kuliah</span>
        <select class="field"><option>Sistem Kendali</option><option>Kecerdasan Artifisial</option>
          <option>Mikrokontroler</option></select></label>
      <label><span class="label">Hari</span>
        <select class="field">${DATA.hari.map(h => `<option>${h}</option>`).join('')}</select></label>
      <div class="row">
        <label style="flex:1"><span class="label">Mulai</span><input class="field" type="time" value="07:00"></label>
        <label style="flex:1"><h2>Selesai</h2><input class="field" type="time" value="09:30"></label>
      </div>
      <label><h2>Ruang</h2><input class="field" id="f_judul" placeholder="Lab Robotika 2"></label>
      <label><span class="label">Pekan</span>
        <select class="field"><option>1 – 16 (seluruh semester)</option><option>1 – 8</option><option>9 – 16</option></select></label>
    </div>
    <div class="privacy" style="margin:16px 0 0;background:var(--accent-soft);color:var(--accent-text)">
      <div>Basis data menolak slot yang bertabrakan dengan jadwal kelas yang sudah ada
      pada hari yang sama, sebelum tersimpan.</div>
    </div>`;

  $('#modal').innerHTML = `
    <div class="scrim" data-act="tutup">
      <form class="modal" id="modalform" onclick="event.stopPropagation()">
        <div class="grab"></div>
        <header><h2>${kind === 'tugas' ? 'Tugas baru' : 'Slot jadwal baru'}</h2>
          <div class="spacer"></div>
          <button type="button" class="iconbtn" data-act="tutup" aria-label="Tutup">${svg('x', 16)}</button>
        </header>
        <div class="body">${body}</div>
        <div class="composer" style="justify-content:flex-end;padding-top:0">
          <button type="button" class="btn ghost" data-act="tutup">Batal</button>
          <button class="btn primary" type="submit">${kind === 'tugas' ? 'Terbitkan' : 'Simpan slot'}</button>
        </div>
      </form>
    </div>`;
  const f = $('#f_judul'); if (f) f.focus();
}
function closeModal() { $('#modal').innerHTML = ''; }

/* ---------- boot -------------------------------------------------------- */

applyTheme();
render();
setInterval(tickCountdown, 1000);
setTimeout(() => toast('Besok: Laporan Praktikum Mikrokontroler', 'Mikrokontroler · dikumpulkan 23:59'), 1400);
