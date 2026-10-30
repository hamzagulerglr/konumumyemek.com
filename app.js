if (
  location.protocol === "http:" &&
  location.hostname !== "localhost" &&
  location.hostname !== "127.0.0.1"
) {
  location.replace("https://" + location.host + location.pathname + location.search + location.hash);
}
const REAL_AUDIO = window.AudioContext || window.webkitAudioContext;
const START_M = 1400;
const ALARM_THRESHOLD_M = 500;
const SUPABASE_PROJECT_ID = "hetcihydnkgbuglsuzcs";
const SUPABASE_URL = window.KONUMUM_SUPABASE_URL || `https://${SUPABASE_PROJECT_ID}.supabase.co`;
const SUPABASE_ANON_KEY = window.KONUMUM_SUPABASE_ANON_KEY || "sb_publishable_Xh8V52jmvs1JFpKX7v8SuA_SFk1DA0Z";
const SUPABASE_SERVICE_ROLE_KEY = window.KONUMUM_SUPABASE_SERVICE_ROLE_KEY || "";
const SUPABASE_ACTIVE_KEY = SUPABASE_ANON_KEY || SUPABASE_SERVICE_ROLE_KEY;

let sbClient = null;
let sbChannel = null;
if (window.supabase && typeof window.supabase.createClient === "function") {
  try {
    sbClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ACTIVE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      realtime: { params: { eventsPerSecond: 20 } }
    });
  } catch { /* fallback */ }
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const toRad = (deg) => (Number(deg) * Math.PI) / 180;
  const dLat = toRad(Number(lat2) - Number(lat1));
  const dLon = toRad(Number(lon2) - Number(lon1));
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return Math.max(0, Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)))));
}

const $ = (id) => document.getElementById(id);
let soundMuted = localStorage.getItem("konumum.web.muted") === "1";

function playTones(freqs, wave = "triangle", ms = 140) {
  if (soundMuted || !REAL_AUDIO) return;
  try {
    const ctx = new REAL_AUDIO();
    freqs.forEach((freq, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = wave;
      osc.frequency.value = freq;
      gain.gain.value = 0.08;
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + (i * (ms + 20)) / 1000);
      osc.stop(ctx.currentTime + (i * (ms + 20) + ms) / 1000);
    });
  } catch { /* autoplay */ }
}

function paintMute() {
  const btn = $("muteBtn");
  if (!btn) return;
  btn.textContent = soundMuted ? "🔇 Sessiz" : "🔊 Ses açık";
  btn.classList.toggle("muted", soundMuted);
  const Silent = function AudioContext() {
    this.createOscillator = () => ({ connect() {}, start() {}, stop() {}, frequency: { value: 0 }, type: "sine" });
    this.createGain = () => ({ connect() {}, gain: { value: 0 } });
    this.destination = {};
    this.currentTime = 0;
    this.close = () => {};
  };
  window.AudioContext = soundMuted ? Silent : REAL_AUDIO;
  window.webkitAudioContext = soundMuted ? Silent : REAL_AUDIO;
}

let seed = null;
let runtime = { menuExtras: {}, menus: {}, profiles: {}, campaigns: [], orders: [] };
let session = null;
let tab = "home";
let poll = null;
let socket = null;
let orderFilter = "all";
const alarmed = new Set();
const seenTickets = new Set();
let dismissedOrderIds = new Set();
let boardClearedAt = Number(localStorage.getItem("konumum.web.clearedAt") || "0");
try {
  const savedDismissed = JSON.parse(localStorage.getItem("konumum.web.dismissed") || "[]");
  if (Array.isArray(savedDismissed)) dismissedOrderIds = new Set(savedDismissed.map(String));
} catch { /* ignore */ }

function sanitizeOrderIdentity(order) {
  if (!order) return order;
  const name = String(order.driverName || order.customer || "").trim();
  if (!name) {
    order.driverName = "Ahmet Yılmaz";
    order.customer = "Ahmet Yılmaz";
  } else {
    order.driverName = name;
    order.customer = name;
  }
  const plate = String(order.plate || "").trim();
  if (!plate) {
    order.plate = "34 KNM 55";
  } else {
    order.plate = plate;
  }
  if (order.items) {
    order.items = String(order.items).replace(" · Canlı Simülasyon", "");
  }
  return order;
}

function filterActiveBoardOrders(orders) {
  return (orders || [])
    .filter((o) => o && !dismissedOrderIds.has(String(o.id)))
    .map(sanitizeOrderIdentity);
}

const PHOTOS = ["🍔", "🍟", "🥤", "🍗", "🌯", "🍕", "🥯", "🥩", "🥗", "🍵", "🫖", "🥛", "🧃", "🧅", "🍽️"];
const ALLERGENS = ["Gluten", "Süt", "Yumurta", "Susam", "Soya", "Fındık", "Ceviz", "Hardal"];
const STATUS_STEPS = ["iletildi", "kabul", "hazir", "yolda", "teslim"];
const STATUS_LABEL = {
  iletildi: "İletildi",
  kabul: "Mutfak kabul",
  hazir: "Hazır",
  yolda: "Yolda",
  kapıda: "Kapıda",
  kapida: "Kapıda",
  teslim: "Teslim",
  iptal: "İptal"
};
const STAFF_TITLE = {
  yonetici: "Yönetici",
  mutfak: "Mutfak (KDS)",
  kasiyer: "Kasiyer / Cam Teslim"
};
let staffPick = "yonetici";
const COMMISSION = 0.12;
const CATS = ["Ana yemek", "Yan", "İçecek"];
const BUSY_CYCLE = ["low", "mid", "high"];
const BUSY_LABEL = { low: "Düşük", mid: "Normal", high: "Yoğun" };

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[ch]));
}

function proximity(meters) {
  const m = Number(meters ?? START_M);
  if (m >= 1000) return { key: "far", color: "#3AF1D7", label: "Yeni sipariş · Yeşil (≥1000 m)" };
  if (m >= 500) return { key: "mid", color: "#FFD129", label: "Orta mesafe · Sarı (500–1000 m)" };
  return { key: "door", color: "#FF4272", label: "Kapıda · Kırmızı (<500 m)" };
}

function formatDistanceEta(meters) {
  const m = Math.max(0, Math.round(Number(meters ?? START_M)));
  if (m === 0) return "0 m · KAPIDA (0 sn)";
  const kmPart = Math.floor(m / 1000);
  const mPart = m % 1000;
  const totalSec = Math.max(3, Math.round(m / 10));
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  const etaText = min > 0
    ? (sec > 0 ? `${min} dk ${sec} sn` : `${min} dk`)
    : `${sec} sn`;
  return `${kmPart > 0 ? `${kmPart} km ${mPart} m` : `${m} m`} (${etaText})`;
}

function extrasFor(id) {
  return runtime.menuExtras[id] || [];
}

function restaurantById(id) {
  const fromSeed = (seed.restaurants || []).find((row) => row.id === id);
  if (fromSeed) return { ...fromSeed, ...((runtime.profiles || {})[id] || {}), id };
  const fromProf = (runtime.profiles || {})[id];
  if (fromProf) return { ...fromProf, id };
  return null;
}

function allRestaurants() {
  const map = new Map();
  (seed.restaurants || []).forEach((row) => {
    map.set(row.id, { ...row, ...((runtime.profiles || {})[row.id] || {}), id: row.id });
  });
  Object.entries(runtime.profiles || {}).forEach(([id, prof]) => {
    if (!map.has(id) && prof && prof.email && prof.password) {
      map.set(id, {
        id,
        bayiKodu: prof.bayiKodu || ("BY-" + id.slice(-4).toUpperCase()),
        officialTitle: prof.officialTitle || prof.branchTitle || "İşletme",
        branchTitle: prof.branchTitle || prof.officialTitle || "Restoran Şubesi",
        email: prof.email,
        password: prof.password,
        phone: prof.phone || "",
        taxNumber: prof.taxNumber || "",
        iban: prof.iban || "",
        address: prof.address || "",
        cuisine: prof.cuisine || "Restoran",
        hours: prof.hours || "09:00-23:00",
        logoMark: prof.logoMark || (prof.branchTitle || "R").slice(0, 2).toUpperCase(),
        logoBg: prof.logoBg || "#3AF1D7",
        logoFg: prof.logoFg || "#0B0F19",
        latitude: Number(prof.latitude || 41.3320),
        longitude: Number(prof.longitude || 36.2730),
        menu: (runtime.menus || {})[id] || []
      });
    }
  });
  return Array.from(map.values());
}

function menuOf(restaurant) {
  const cloud = (runtime.menus || {})[restaurant.id];
  if (cloud && cloud.length) return cloud;
  return [...(restaurant.menu || []), ...extrasFor(restaurant.id)];
}

function kitchenOrders() {
  if (!session) return [];
  return (runtime.orders || []).filter((o) =>
    o.restaurantId === session.id && !["teslim", "iptal"].includes(o.status)
  );
}

function liveOrders() {
  return kitchenOrders();
}

function deviceId() {
  let id = localStorage.getItem("konumum.deviceId");
  if (!id) {
    id = "dev-" + Math.random().toString(36).slice(2, 10);
    localStorage.setItem("konumum.deviceId", id);
  }
  return id;
}

function staffOf() {
  return session?.staffRole || "yonetici";
}

function canKitchen() {
  return ["yonetici", "mutfak"].includes(staffOf());
}

function canCash() {
  return ["yonetici", "kasiyer"].includes(staffOf());
}

function canManage() {
  return staffOf() === "yonetici";
}

function isSuperAdmin() {
  if (!session) return false;
  if (session.superAdmin) return true;
  const em = String(session.email || "").trim().toLowerCase();
  const by = String(session.bayiKodu || "").trim().toLowerCase();
  const id = String(session.id || "").trim().toLowerCase();
  const br = String(session.branchTitle || "").trim().toLowerCase();
  return (
    em === "hamza_guler@hotmail.com" ||
    em === "hamzaguler@outlook.com" ||
    em === "hghamzaguler@gmail.com" ||
    em === "admin@konumumyemek.com" ||
    em === "info@konumumyemek.com" ||
    em.includes("hamza") ||
    by === "by-9822" ||
    id.includes("hmzglr") ||
    br.includes("hmzglr")
  ) && canManage();
}

function profileOf(id) {
  return (runtime.profiles || {})[id || session?.id] || {};
}

function isWithinHours(hoursStr) {
  const m = /^(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})$/.exec(String(hoursStr || "").trim());
  if (!m) return true;
  const openMin = Number(m[1]) * 60 + Number(m[2]);
  const closeMin = Number(m[3]) * 60 + Number(m[4]);
  const now = new Date();
  const curMin = now.getHours() * 60 + now.getMinutes();
  if (closeMin <= openMin) {
    return curMin >= openMin || curMin < closeMin;
  }
  return curMin >= openMin && curMin < closeMin;
}

function storeOpenState(id) {
  const p = profileOf(id || session?.id);
  const rest = restaurantById(id || session?.id) || {};
  const hours = p.hours || rest.hours || "10:00-23:00";
  const within = isWithinHours(hours);
  const manualOpen = p.open !== false;
  return {
    open: manualOpen,
    withinHours: within,
    effectiveOpen: manualOpen && within,
    hours,
    busy: p.busy || "mid"
  };
}

function dishVars(dish) {
  return (dish.variations && dish.variations.length)
    ? dish.variations
    : [{ id: "std", name: "Standart", priceDelta: 0 }];
}

function guessCat(name) {
  const n = String(name || "").toLowerCase();
  if (n.includes("cola") || n.includes("kola") || n.includes("ayran") || n.includes("çay") || n.includes("shake")) return "İçecek";
  if (n.includes("patates") || n.includes("halka") || n.includes("sos") || n.includes("termos")) return "Yan";
  return "Ana yemek";
}

function mapSupabaseOrderRow(o = {}, tr = {}) {
  const lat = Number(tr.latitude ?? o.latitude ?? 41.3320);
  const lon = Number(tr.longitude ?? o.longitude ?? 36.2730);
  const restId = o.restaurant_id || tr.restaurant_id || o.restaurantId || (session && session.id) || "mcd-samsun";
  let rawMeters = tr.distance_meters ?? tr.meters ?? o.distance_meters ?? o.meters;
  if (rawMeters === undefined || rawMeters === null) {
    const prof = (runtime && runtime.profiles && runtime.profiles[restId]) || {};
    const rLat = Number(prof.latitude ?? (session && session.id === restId ? session.latitude : null));
    const rLon = Number(prof.longitude ?? (session && session.id === restId ? session.longitude : null));
    if (Number.isFinite(rLat) && Number.isFinite(rLon) && Number.isFinite(lat) && Number.isFinite(lon)) {
      rawMeters = haversineMeters(lat, lon, rLat, rLon);
    } else {
      rawMeters = START_M;
    }
  }
  const meters = Math.max(0, Number(rawMeters));
  const rawStatus = String(tr.order_status || tr.status || o.order_status || o.status || "yolda").toLowerCase();
  const status = ["iletildi", "kabul", "hazir", "yolda", "kapıda", "kapida", "teslim", "iptal"].includes(rawStatus)
    ? rawStatus
    : "yolda";
  const active = !["teslim", "iptal"].includes(status);
  const resolvedId = String(o.id || tr.order_id || tr.id || "sim-live-1");
  return sanitizeOrderIdentity({
    id: resolvedId,
    restaurantId: restId,
    driverName: o.driver_name || o.driverName || tr.driver_name || tr.customer_name || o.customer_name || o.customer || "Ahmet Yılmaz",
    customer: o.customer_name || o.customer || tr.customer_name || o.driver_name || o.driverName || "Ahmet Yılmaz",
    plate: o.plate || tr.plate || tr.car_plate || "34 KNM 55",
    items: (o.items || tr.items || "1× Big Mac Menü, 1× Büyük Boy Patates").replace(" · Canlı Simülasyon", ""),
    payment: o.payment_method || o.payment || "Metropol Card",
    total: Number(o.total_amount ?? o.total ?? tr.total ?? 340),
    status,
    cancelReason: o.cancel_reason || o.cancelReason || "",
    prepMinutes: Number(o.prep_minutes ?? o.prepMinutes ?? 0),
    lane: o.lane || "",
    stall: Number(o.stall ?? 0),
    speaker: Number(o.speaker ?? 0),
    speakerMatched: Boolean(o.speaker_matched ?? o.speakerMatched),
    atDoor: Boolean(o.at_door ?? tr.at_door ?? o.atDoor ?? meters === 0),
    seenCar: Boolean(o.seen_car ?? o.seenCar),
    source: o.source || "supabase-live",
    latitude: lat,
    longitude: lon,
    meters,
    distance_meters: meters,
    eta_seconds: Number(tr.eta_seconds ?? Math.max(0, Math.round(meters / 10))),
    trigger_alarm: Boolean(tr.trigger_alarm ?? (active && meters < ALARM_THRESHOLD_M)),
    updatedAt: tr.updated_at || o.updated_at || o.updatedAt || new Date().toISOString()
  });
}

function mergeProfilesSafe(target = {}, incoming = {}) {
  const out = { ...target };
  Object.entries(incoming || {}).forEach(([id, prof]) => {
    if (!prof || typeof prof !== "object") return;
    const cur = out[id] || {};
    const merged = { ...cur, ...prof };
    if (cur.password && !prof.password) merged.password = cur.password;
    if (cur.email && !prof.email) merged.email = cur.email;
    if (cur.branchTitle && !prof.branchTitle) merged.branchTitle = cur.branchTitle;
    out[id] = merged;
  });
  return out;
}

function supabaseHeaders(prefer) {
  const h = {
    "Content-Type": "application/json",
    apikey: SUPABASE_ACTIVE_KEY,
    Authorization: `Bearer ${SUPABASE_ACTIVE_KEY}`
  };
  if (prefer) h.Prefer = prefer;
  return h;
}

function applyStateRecord(key, payload) {
  if (!key || !payload) return false;
  if (key === "profiles") {
    runtime.profiles = mergeProfilesSafe(runtime.profiles, payload);
    return true;
  }
  if (String(key).startsWith("account:") && payload.id) {
    runtime.profiles = mergeProfilesSafe(runtime.profiles, { [payload.id]: payload });
    return true;
  }
  if (["menus", "menuExtras"].includes(key)) {
    runtime[key] = { ...(runtime[key] || {}), ...payload };
    return true;
  }
  if (key === "campaigns" && Array.isArray(payload) && payload.length) {
    runtime.campaigns = payload;
    return true;
  }
  if (key === "supportTickets" && Array.isArray(payload)) {
    runtime.supportTickets = payload;
    return true;
  }
  return false;
}

function isSystemStateOrderRow(o) {
  if (!o) return false;
  const id = String(o.id || "");
  return id.startsWith("__state_") || o.source === "system_state" || o.restaurant_id === "__system__";
}

async function fetchDirectSupabaseState() {
  try {
    let stateRows = null;
    let ordRows = [];
    let trRows = [];

    const restFetch = fetch(`${SUPABASE_URL}/rest/v1/restaurant_state?select=key,payload`, {
      headers: supabaseHeaders(),
      cache: "no-store"
    }).then((r) => (r.ok ? r.json() : null)).catch(() => null);

    const ordFetch = fetch(`${SUPABASE_URL}/rest/v1/orders?select=*&limit=250`, {
      headers: supabaseHeaders(),
      cache: "no-store"
    }).then((r) => (r.ok ? r.json() : [])).catch(() => []);

    const trFetch = fetch(`${SUPABASE_URL}/rest/v1/live_tracking?select=*`, {
      headers: supabaseHeaders(),
      cache: "no-store"
    }).then((r) => (r.ok ? r.json() : [])).catch(() => []);

    const timeout = new Promise((resolve) => setTimeout(() => resolve([null, [], []]), 7000));
    [stateRows, ordRows, trRows] = await Promise.race([
      Promise.all([restFetch, ordFetch, trFetch]),
      timeout
    ]);

    let gotState = false;
    (stateRows || []).forEach((item) => {
      if (item && applyStateRecord(item.key, item.payload)) gotState = true;
    });

    const safeTr = Array.isArray(trRows) ? trRows : [];
    const rawOrd = Array.isArray(ordRows) ? ordRows : [];
    const safeOrd = [];
    rawOrd.forEach((o) => {
      if (isSystemStateOrderRow(o)) {
        const key = String(o.id || "").replace(/^__state_/, "");
        try {
          const parsedPayload = typeof o.items === "string" ? JSON.parse(o.items) : o.items;
          if (applyStateRecord(key, parsedPayload)) gotState = true;
        } catch { /* ignore */ }
      } else {
        safeOrd.push(o);
      }
    });

    const trById = {};
    safeTr.forEach((tr) => {
      const key = tr && (tr.order_id || tr.id);
      if (key) trById[String(key)] = tr;
    });
    const merged = [];
    const seenIds = new Set();
    safeOrd.forEach((o) => {
      const key = String(o.id);
      seenIds.add(key);
      merged.push(mapSupabaseOrderRow(o, trById[key] || {}));
    });
    safeTr.forEach((tr) => {
      const key = String(tr.order_id || tr.id || "sim-live-1");
      if (!seenIds.has(key) && !String(key).startsWith("__state_")) {
        seenIds.add(key);
        merged.push(mapSupabaseOrderRow({}, tr));
      }
    });
    if (merged.length > 0) {
      const existing = (runtime.orders || []).filter((o) => !seenIds.has(String(o.id)) && !isSystemStateOrderRow(o));
      runtime.orders = filterActiveBoardOrders([...merged, ...existing]);
    }
    if (gotState) {
      localStorage.setItem("konumum.web.runtime", JSON.stringify(runtime));
    }
    return gotState || merged.length > 0;
  } catch {
    return false;
  }
}

async function syncLocalAccountsToCloud() {
  const accounts = Object.entries(runtime.profiles || {}).filter(
    ([, prof]) => prof && prof.email && prof.password
  );
  if (!accounts.length) return;
  await persist();
}

async function boot() {
  seed = await (await fetch("data/seed.json", { cache: "no-store" })).json();
  try { runtime = await (await fetch("data/runtime.json?t=" + Date.now(), { cache: "no-store" })).json(); } catch { /* local */ }
  const local = localStorage.getItem("konumum.web.runtime");
  if (local) {
    try {
      const parsed = JSON.parse(local);
      runtime.menuExtras = { ...parsed.menuExtras, ...runtime.menuExtras };
      runtime.profiles = mergeProfilesSafe(runtime.profiles, parsed.profiles);
      if (Array.isArray(parsed.orders)) {
        runtime.orders = parsed.orders;
      }
    } catch { /* ignore */ }
  }
  if (boardClearedAt > 0 && (!local || !JSON.parse(local || "{}").orders?.length)) {
    runtime.orders = [];
  }
  runtime.orders = filterActiveBoardOrders(runtime.orders);
  (runtime.orders || []).forEach((order) => {
    if (order.id) seenTickets.add(order.id);
  });
  bindStaffChips();
  paintShell();
  paintMute();
  await fetchDirectSupabaseState();
  await syncLocalAccountsToCloud();
  const saved = localStorage.getItem("konumum.web.session");
  if (saved) {
    try {
      const parsed = JSON.parse(saved);
      if (parsed.role === "customer" || !parsed.authToken) {
        localStorage.removeItem("konumum.web.session");
      } else {
        session = findRestaurant(parsed.email, parsed.authToken);
        if (session) {
          session.staffRole = parsed.staffRole || "yonetici";
          enter(false, session);
        } else {
          localStorage.removeItem("konumum.web.session");
        }
      }
    } catch {
      localStorage.removeItem("konumum.web.session");
    }
  }
  const muteBtn = $("muteBtn");
  if (muteBtn) muteBtn.onclick = () => {
    soundMuted = !soundMuted;
    localStorage.setItem("konumum.web.muted", soundMuted ? "1" : "0");
    paintMute();
  };
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.getRegistrations().then((regs) => {
      regs.forEach((reg) => reg.unregister());
    }).catch(() => {});
  }
  const legalLink = $("openLegal");
  if (legalLink) legalLink.onclick = (event) => {
    event.preventDefault();
    const modal = $("legalModal");
    if (modal) modal.classList.toggle("hidden");
  };
}

function paintShell() {
  document.body.classList.remove("shop");
  document.body.classList.add("desk");
  document.querySelectorAll(".chrome").forEach((el) => el.remove());
}

function findRestaurant(identifier, password) {
  const key = String(identifier || "").trim().toLowerCase();
  const pin = String(password || "").trim();
  if (!key || !pin) return null;
  if (
    (key === "admin@konumumyemek.com" || key === "info@konumumyemek.com" || key === "hamza_guler@hotmail.com") &&
    (pin === "416800" || pin === "4126800")
  ) {
    const first = allRestaurants().find((r) => String(r.email || "").toLowerCase().includes("hamza")) || allRestaurants()[0] || {
      id: "hmzglr-9822",
      bayiKodu: "BY-9822",
      branchTitle: "Konumum Yemek Genel Merkez",
      officialTitle: "Konumum Yemek Platform Yönetimi",
      email: "admin@konumumyemek.com"
    };
    return {
      ...first,
      ...(runtime.profiles?.[first.id] || {}),
      id: first.id,
      email: "admin@konumumyemek.com",
      role: "restaurant",
      staffRole: "yonetici",
      superAdmin: true
    };
  }
  const r = allRestaurants().find((row) => {
    const emailMatch = String(row.email || "").toLowerCase() === key;
    const codeMatch = String(row.bayiKodu || "").toLowerCase() === key;
    const effectivePass = String((runtime.profiles?.[row.id]?.password) || row.password || "").trim();
    return (emailMatch || codeMatch) && effectivePass === pin;
  });
  if (r) return { ...r, ...(runtime.profiles[r.id] || {}), id: r.id, role: "restaurant" };
  return null;
}

function findRestaurantByEmail(identifier) {
  const key = String(identifier || "").trim().toLowerCase();
  if (!key) return null;
  const r = allRestaurants().find((row) =>
    String(row.email || "").toLowerCase() === key || String(row.bayiKodu || "").toLowerCase() === key
  );
  if (r) return { ...r, ...(runtime.profiles[r.id] || {}), id: r.id, role: "restaurant" };
  return null;
}

function formatTrIban(raw) {
  let clean = String(raw || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (clean && !clean.startsWith("TR")) {
    clean = "TR" + clean.replace(/^[A-Z]+/, "");
  }
  if (clean.startsWith("TR")) {
    clean = "TR" + clean.slice(2).replace(/\D/g, "");
  }
  clean = clean.slice(0, 26);
  return clean.replace(/(.{4})/g, "$1 ").trim();
}

function isValidTrIban(raw) {
  const clean = String(raw || "").toUpperCase().replace(/\s+/g, "");
  return /^TR\d{24}$/.test(clean);
}

function isValidTaxOrTckn(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  return digits.length === 10 || digits.length === 11;
}

function resetRegisterForm() {
  ["regBranchTitle", "regOfficialTitle", "regTaxOffice", "regTaxNumber", "regIban", "regEmail", "regPhone", "regPassword", "regPassword2", "regCuisine", "regAddress"].forEach((id) => {
    const el = $(id);
    if (el) el.value = "";
  });
  if ($("regHours")) $("regHours").value = "09:00-23:00";
  if ($("regKvkkOk")) $("regKvkkOk").checked = true;
  if ($("regMerchantContractOk")) $("regMerchantContractOk").checked = true;
  if ($("regFoodSafetyOk")) $("regFoodSafetyOk").checked = true;
  if ($("regErr")) $("regErr").textContent = "";
  if ($("regOk")) $("regOk").textContent = "";
}

function resetAuthForms() {
  resetRegisterForm();
  if ($("email")) $("email").value = "";
  if ($("password")) $("password").value = "";
  if ($("err")) $("err").textContent = "";
  const modeLoginBtn = $("modeLoginBtn");
  const modeRegisterBtn = $("modeRegisterBtn");
  const loginFormPane = $("loginFormPane");
  const registerFormPane = $("registerFormPane");
  if (modeLoginBtn && modeRegisterBtn && loginFormPane && registerFormPane) {
    modeLoginBtn.classList.add("on");
    modeRegisterBtn.classList.remove("on");
    loginFormPane.classList.remove("hidden");
    registerFormPane.classList.add("hidden");
  }
}

function bindStaffChips() {
  [...document.querySelectorAll("#staffRoles [data-staff]")].forEach((btn) => {
    btn.onclick = () => {
      staffPick = btn.dataset.staff;
      [...document.querySelectorAll("#staffRoles [data-staff]")].forEach((el) => {
        el.classList.toggle("on", el === btn);
      });
    };
  });
  const modeLoginBtn = $("modeLoginBtn");
  const modeRegisterBtn = $("modeRegisterBtn");
  const loginFormPane = $("loginFormPane");
  const registerFormPane = $("registerFormPane");
  if (modeLoginBtn && modeRegisterBtn && loginFormPane && registerFormPane) {
    modeLoginBtn.onclick = () => {
      modeLoginBtn.classList.add("on");
      modeRegisterBtn.classList.remove("on");
      loginFormPane.classList.remove("hidden");
      registerFormPane.classList.add("hidden");
      if ($("err")) $("err").textContent = "";
    };
    modeRegisterBtn.onclick = () => {
      resetRegisterForm();
      modeRegisterBtn.classList.add("on");
      modeLoginBtn.classList.remove("on");
      registerFormPane.classList.remove("hidden");
      loginFormPane.classList.add("hidden");
    };
  }
  const regBtn = $("registerBtn");
  if (regBtn) regBtn.onclick = tryRegister;
  if ($("regIban")) {
    $("regIban").oninput = (e) => {
      e.target.value = formatTrIban(e.target.value);
    };
  }
  if ($("regTaxNumber")) {
    $("regTaxNumber").oninput = (e) => {
      e.target.value = String(e.target.value || "").replace(/\D/g, "").slice(0, 11);
    };
  }
  const openSupportBtn = $("openSupportBtn");
  const supportModal = $("supportModal");
  if (openSupportBtn && supportModal) {
    openSupportBtn.onclick = () => {
      supportModal.classList.toggle("hidden");
    };
  }
  const sendSupportBtn = $("sendSupportBtn");
  if (sendSupportBtn) {
    sendSupportBtn.onclick = submitSupportTicket;
  }
}

async function submitSupportTicket() {
  const errEl = $("supErr");
  const okEl = $("supOk");
  if (errEl) errEl.textContent = "";
  if (okEl) okEl.textContent = "";
  const name = String($("supName")?.value || "").trim();
  const contact = String($("supContact")?.value || "").trim();
  const msg = String($("supMsg")?.value || "").trim();
  if (!name || !contact || !msg) {
    if (errEl) errEl.textContent = "Lütfen adınızı/işletmenizi, iletişim bilginizi ve mesajınızı yazın.";
    return;
  }
  await fetchDirectSupabaseState();
  runtime.supportTickets = Array.isArray(runtime.supportTickets) ? runtime.supportTickets : [];
  runtime.supportTickets.unshift({
    id: "SUP-" + Date.now(),
    name,
    contact,
    message: msg,
    status: "bekliyor",
    createdAt: new Date().toISOString()
  });
  await persist();
  if ($("supName")) $("supName").value = "";
  if ($("supContact")) $("supContact").value = "";
  if ($("supMsg")) $("supMsg").value = "";
  if (okEl) okEl.textContent = "Talebiniz Konumum Genel Merkez'e ve info@konumumyemek.com sistemine iletildi. En kısa sürede dönüş yapılacaktır.";
}

function switchBranch(id, persistSession = true) {
  const row = restaurantById(id);
  if (!row || !session) return;
  const staffRole = session.staffRole || "yonetici";
  const keepSuper = Boolean(session.superAdmin || isSuperAdmin());
  session = { ...row, ...(runtime.profiles[row.id] || {}), id: row.id, role: "restaurant", staffRole, authToken: row.password, superAdmin: keepSuper };
  if (persistSession) storeSession();
  updateHeaderWho();
}

function updateHeaderWho() {
  if (!session || !$("who")) return;
  const roleLabel = STAFF_TITLE[session.staffRole || "yonetici"] || session.staffRole;
  const st = storeOpenState(session.id);
  const statusBadge = st.effectiveOpen
    ? `<span style="color:#38F27A;font-weight:800">● AÇIK (${esc(st.hours)})</span>`
    : `<span style="color:#FF4272;font-weight:800">● KAPALI (${st.open ? `Mesai Dışı · ${esc(st.hours)}` : `Manuel Kapalı · ${esc(st.hours)}`})</span>`;
  $("who").innerHTML = `${esc(session.branchTitle)} · ${esc(roleLabel)} · ${statusBadge}`;
}

$("login").onclick = tryLogin;
$("password").addEventListener("keydown", (event) => {
  if (event.key === "Enter") tryLogin();
});

async function tryLogin() {
  if (!$("kvkkOk")?.checked) {
    $("err").textContent = "Devam için KVKK ve işletme veri işleme onayı gerekli";
    return;
  }
  const emailVal = String($("email").value || "").trim();
  const passVal = String($("password").value || "").trim();
  if (!emailVal || !passVal) {
    $("err").textContent = "Lütfen kurumsal e-posta/bayi kodu ve şifrenizi eksiksiz girin.";
    return;
  }
  $("err").textContent = "";
  let user = findRestaurant(emailVal, passVal);
  if (!user) {
    try {
      const acctOrderKey = "__state_account:" + emailVal.toLowerCase();
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(acctOrderKey)}&select=id,items`,
        { headers: supabaseHeaders(), cache: "no-store" }
      );
      if (res.ok) {
        const rows = await res.json();
        (rows || []).forEach((item) => {
          if (item && item.items) {
            try {
              const parsed = JSON.parse(item.items);
              if (parsed && parsed.id) {
                runtime.profiles = mergeProfilesSafe(runtime.profiles, { [parsed.id]: parsed });
              }
            } catch { /* ignore */ }
          }
        });
      }
    } catch { /* fallback */ }
    await fetchDirectSupabaseState();
    user = findRestaurant(emailVal, passVal);
  }
  if (!user) {
    $("err").textContent = "Restoran e-posta/bayi kodu veya şifre hatalı.";
    return;
  }
  await persist();
  user.staffRole = staffPick;
  user.authToken = passVal;
  enter(true, user);
}

async function tryRegister() {
  const errEl = $("regErr");
  const okEl = $("regOk");
  if (errEl) errEl.textContent = "";
  if (okEl) okEl.textContent = "";

  if (!$("regKvkkOk")?.checked || !$("regMerchantContractOk")?.checked || !$("regFoodSafetyOk")?.checked) {
    if (errEl) errEl.textContent = "Devam için KVKK Aydınlatma, Üye İşyeri & IBAN Hakediş Sözleşmesi ve Gıda Güvenliği beyanlarının tamamını onaylamanız zorunludur.";
    return;
  }
  const branchTitle = String($("regBranchTitle")?.value || "").trim();
  const officialTitle = String($("regOfficialTitle")?.value || "").trim() || branchTitle;
  const taxOffice = String($("regTaxOffice")?.value || "").trim();
  const taxNumber = String($("regTaxNumber")?.value || "").replace(/\D/g, "").trim();
  const rawIban = String($("regIban")?.value || "").trim();
  const iban = rawIban ? formatTrIban(rawIban) : "";
  const email = String($("regEmail")?.value || "").trim().toLowerCase();
  const phone = String($("regPhone")?.value || "").trim();
  const password = String($("regPassword")?.value || "").trim();
  const password2 = String($("regPassword2")?.value || "").trim();
  const cuisine = String($("regCuisine")?.value || "").trim() || "Restoran & Mutfak";
  const hours = String($("regHours")?.value || "").trim() || "09:00-23:00";
  const address = String($("regAddress")?.value || "").trim();

  if (!branchTitle || !email || !password) {
    if (errEl) errEl.textContent = "Lütfen en azından Restoran / Şube Adı, Kurumsal E-posta ve Şifre alanlarını doldurun (diğer bilgileri üyelik sonrasında Restoran Profili sekmesinden tamamlayabilirsiniz).";
    return;
  }
  if (taxNumber && !isValidTaxOrTckn(taxNumber)) {
    if (errEl) errEl.textContent = "Vergi Kimlik No (10 hane) veya TCKN (11 hane) eksik/hatalı görünüyor. Şimdi boş bırakıp daha sonra Restoran Profili sekmesinden tamamlayabilirsiniz.";
    return;
  }
  if (iban && iban !== "TR" && !isValidTrIban(iban)) {
    if (errEl) errEl.textContent = "Girilen IBAN 26 haneli TR formatında değil. Şimdi boş bırakıp daha sonra Restoran Profili sekmesinden tamamlayabilirsiniz.";
    return;
  }
  if (password.length < 4) {
    if (errEl) errEl.textContent = "Şifreniz en az 4 karakter olmalıdır.";
    return;
  }
  if (password2 && password !== password2) {
    if (errEl) errEl.textContent = "Girdiğiniz şifreler birbiriyle eşleşmiyor.";
    return;
  }

  await fetchDirectSupabaseState();
  const existing = findRestaurantByEmail(email);

  const slug = branchTitle
    .toLowerCase()
    .replace(/[^a-z0-9ğüşıöç]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 18) || "isletme";
  const randCode = Math.floor(1000 + Math.random() * 9000);
  const id = (existing && existing.id) ? existing.id : `${slug}-${randCode}`;
  const bayiKodu = (existing && existing.bayiKodu) ? existing.bayiKodu : `BY-${randCode}`;
  const logoMark = branchTitle.slice(0, 2).toUpperCase();

  let regLat = Number((existing && existing.latitude) || 41.3320);
  let regLng = Number((existing && existing.longitude) || 36.2730);
  if (navigator.geolocation && (!existing || !existing.latitude)) {
    try {
      const pos = await new Promise((resolve) => {
        navigator.geolocation.getCurrentPosition(resolve, () => resolve(null), {
          enableHighAccuracy: true,
          timeout: 3500
        });
      });
      if (pos && pos.coords) {
        regLat = Number(pos.coords.latitude.toFixed(6));
        regLng = Number(pos.coords.longitude.toFixed(6));
      }
    } catch { /* fallback default */ }
  }

  const newProfile = {
    ...(existing || {}),
    id,
    bayiKodu,
    officialTitle,
    branchTitle,
    email,
    password,
    phone,
    taxOffice,
    taxNumber,
    iban,
    address,
    cuisine,
    hours,
    open: true,
    busy: "low",
    logoMark,
    logoBg: (existing && existing.logoBg) || "#3AF1D7",
    logoFg: (existing && existing.logoFg) || "#0B0F19",
    latitude: regLat,
    longitude: regLng,
    kvkkApprovedAt: new Date().toISOString(),
    merchantContractApprovedAt: new Date().toISOString(),
    foodSafetyApprovedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };

  runtime.profiles = runtime.profiles || {};
  runtime.profiles[id] = newProfile;
  runtime.menus = runtime.menus || {};
  if (!runtime.menus[id] || !runtime.menus[id].length) {
    runtime.menus[id] = [
      {
        id: `${id}-m1`,
        name: `${branchTitle} Özel Menü`,
        price: 220,
        photo: "🍔",
        photoBg: "#1a2433",
        kcal: 540,
        stock: 50,
        category: "Ana yemek",
        allergens: ["Gluten"],
        variations: [
          { id: "std", name: "Standart", priceDelta: 0 },
          { id: "buyuk", name: "Büyük Seçim", priceDelta: 45 }
        ],
        soldOut: false
      },
      {
        id: `${id}-m2`,
        name: "Büyük Boy Patates Kızartması",
        price: 75,
        photo: "🍟",
        photoBg: "#1a2433",
        kcal: 380,
        stock: 60,
        category: "Yan",
        allergens: [],
        variations: [{ id: "std", name: "Standart", priceDelta: 0 }],
        soldOut: false
      },
      {
        id: `${id}-m3`,
        name: "Soğuk İçecek / Ayran",
        price: 45,
        photo: "🥤",
        photoBg: "#1a2433",
        kcal: 120,
        stock: 80,
        category: "İçecek",
        allergens: [],
        variations: [{ id: "std", name: "Standart", priceDelta: 0 }],
        soldOut: false
      }
    ];
  }

  await persist();

  if (okEl) {
    okEl.textContent = `Üyeliğiniz buluta taşındı! Bayi Kodunuz: ${bayiKodu}. Panele yönlendiriliyorsunuz...`;
  }

  const user = findRestaurant(email, password);
  resetRegisterForm();
  if (user) {
    user.staffRole = "yonetici";
    user.authToken = password;
    enter(true, user);
  }
}

function enter(persistSession, user = session) {
  session = user;
  session.role = "restaurant";
  if (session.superAdmin) session.staffRole = "yonetici";
  if (persistSession) storeSession();
  $("loginCard").classList.add("hidden");
  $("app").classList.remove("hidden");
  paintShell();
  updateHeaderWho();
  connectRealtime();
  showTab(session.superAdmin ? "hq" : (!canKitchen() ? "orders" : "home"));
}

function storeSession() {
  if (!session) return;
  localStorage.setItem("konumum.web.session", JSON.stringify({
    email: session.email,
    authToken: session.authToken || session.password || "",
    role: "restaurant",
    staffRole: session.staffRole || "yonetici",
    superAdmin: Boolean(session.superAdmin),
    branchId: session.id,
    deviceId: deviceId()
  }));
}

function doLogout() {
  stopTimers();
  session = null;
  localStorage.removeItem("konumum.web.session");
  resetAuthForms();
  $("app").classList.add("hidden");
  $("loginCard").classList.remove("hidden");
  paintShell();
}

function stopTimers() {
  if (poll) clearInterval(poll);
  poll = null;
  if (sbChannel && sbClient) {
    try { sbClient.removeChannel(sbChannel); } catch { /* ignore */ }
    sbChannel = null;
  }
  if (socket) {
    try { socket.close(); } catch { /* ignore */ }
    socket = null;
  }
}

function doorAlarm(order) {
  if (!order || alarmed.has(order.id)) return;
  if (Number(order.meters) !== 0 && !order.atDoor && !["kapıda", "kapida"].includes(order.status)) return;
  alarmed.add(order.id);
  const banner = $("doorAlarm");
  if (banner) {
    banner.textContent = `🚨 ARAÇ KAPIDA (0 m) · ${order.plate} · Paketi camdan teslim edin`;
    banner.classList.add("on");
    setTimeout(() => banner.classList.remove("on"), 5500);
  }
  playTones([880, 1175, 880], "square", 240);
}

function ticketPing(order) {
  if (!order || seenTickets.has(order.id)) return;
  seenTickets.add(order.id);
  if (!session) return;
  if (order.restaurantId !== session.id) return;
  const banner = $("ticketAlarm");
  if (banner) {
    banner.textContent = `🔔 Yeni araç siparişi · ${order.plate || ""} · ${formatDistanceEta(order.meters)}`;
    banner.classList.add("on");
    setTimeout(() => banner.classList.remove("on"), 4200);
  }
  playTones([587, 784], "triangle", 160);
}

const sub500Alarmed = new Set();

function approach500Alarm(order) {
  if (!order || sub500Alarmed.has(order.id)) return;
  if (!session || order.restaurantId !== session.id) return;
  if (["teslim", "iptal"].includes(order.status)) return;
  sub500Alarmed.add(order.id);
  const banner = $("ticketAlarm");
  if (banner) {
    banner.textContent = `🚨 KAPI ÖNÜ YAKLAŞIM (<500 m) · ${order.plate || ""} · ${formatDistanceEta(order.meters)}`;
    banner.classList.add("on");
    setTimeout(() => banner.classList.remove("on"), 4500);
  }
  playTones([740, 987], "sawtooth", 180);
}

function applyCloudEvent(event) {
  if (!event || !event.type) return;
  if (event.type === "snapshot" && event.state) {
    runtime = Object.assign(runtime, event.state);
    runtime.orders = filterActiveBoardOrders(runtime.orders);
  }
  if (event.type === "order.upsert" && event.order) {
    dismissedOrderIds.delete(String(event.order.id));
    localStorage.setItem("konumum.web.dismissed", JSON.stringify([...dismissedOrderIds]));
    sanitizeOrderIdentity(event.order);
    if (event.trigger_alarm !== undefined) {
      event.order.trigger_alarm = Boolean(event.trigger_alarm);
    }
    const next = [];
    let found = false;
    (runtime.orders || []).forEach((row) => {
      if (row.id === event.order.id) {
        next.push(event.order);
        found = true;
      } else next.push(row);
    });
    if (!found) next.unshift(event.order);
    runtime.orders = next;
    if (Number(event.order.meters) === 0) doorAlarm(event.order);
    else if (event.trigger_alarm || event.order.trigger_alarm) approach500Alarm(event.order);
    if (event.order.status === "iletildi") ticketPing(event.order);
  }
  if (event.type === "order.door") doorAlarm(event.order);
  if (event.type === "menus" && event.menus) runtime.menus = event.menus;
  if (event.type === "campaigns" && event.campaigns) runtime.campaigns = event.campaigns;
  if (!session) return;
  updateHeaderWho();
  if (tab === "home") {
    bindOps();
    renderKds();
    renderLiveList();
    draw();
  }
  if (tab === "orders") renderOrders();
  if (tab === "menu") renderMenu();
  if (tab === "campaigns") renderCampaigns();
  if (tab === "reports") renderReports();
  if (tab === "profile") renderProfile();
}

function connectRealtime() {
  const el = $("wsStatus");
  if (sbClient && !sbChannel) {
    sbChannel = sbClient
      .channel("konumum-kds-realtime")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "live_tracking" },
        (payload) => {
          const tr = payload.new || payload.old || {};
          const rowId = String(tr.order_id || tr.id || "sim-live-1");
          const existing = (runtime.orders || []).find((o) => String(o.id) === rowId) || {
            id: rowId,
            restaurant_id: tr.restaurant_id || (session && session.id) || "mcd-samsun",
            plate: tr.plate || tr.car_plate || "34 KNM 55",
            order_status: tr.order_status || tr.status || "yolda"
          };
          const mapped = mapSupabaseOrderRow(existing, tr);
          sub500Alarmed.delete(mapped.id);
          applyCloudEvent({
            type: "order.upsert",
            order: mapped,
            trigger_alarm: mapped.trigger_alarm
          });
        }
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "orders" },
        (payload) => {
          if (payload.eventType === "DELETE" && payload.old?.id) {
            runtime.orders = (runtime.orders || []).filter((o) => o.id !== payload.old.id);
            applyCloudEvent({ type: "snapshot", state: runtime });
            return;
          }
          const ord = payload.new || {};
          if (!ord.id) return;
          if (isSystemStateOrderRow(ord)) {
            const key = String(ord.id).replace(/^__state_/, "");
            try {
              const parsed = typeof ord.items === "string" ? JSON.parse(ord.items) : ord.items;
              if (applyStateRecord(key, parsed)) {
                localStorage.setItem("konumum.web.runtime", JSON.stringify(runtime));
                applyCloudEvent({ type: "snapshot", state: runtime });
              }
            } catch { /* ignore */ }
            return;
          }
          const existing = (runtime.orders || []).find((o) => o.id === ord.id) || {};
          const mapped = mapSupabaseOrderRow(ord, {
            latitude: existing.latitude,
            longitude: existing.longitude,
            distance_meters: existing.meters ?? START_M,
            eta_seconds: existing.eta_seconds,
            trigger_alarm: existing.trigger_alarm,
            at_door: ord.at_door ?? existing.atDoor
          });
          applyCloudEvent({
            type: "order.upsert",
            order: mapped,
            trigger_alarm: mapped.trigger_alarm
          });
        }
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "restaurant_state" },
        (payload) => {
          const row = payload.new || {};
          if (row.key && ["menus", "menuExtras", "profiles", "campaigns"].includes(row.key) && row.payload) {
            runtime[row.key] = row.payload;
            applyCloudEvent({ type: "snapshot", state: runtime });
          }
        }
      )
      .on("broadcast", { event: "order.upsert" }, (msg) => {
        if (msg && msg.payload) applyCloudEvent(msg.payload);
      })
      .subscribe((status) => {
        if (!el) return;
        if (status === "SUBSCRIBED") {
          el.textContent = "● Canlı Radar & Bulut Aktif";
          el.style.color = "#3AF1D7";
        }
      });
  }
  if (!socket || (socket.readyState !== WebSocket.OPEN && socket.readyState !== WebSocket.CONNECTING)) {
    const isLocalhost = location.hostname === "localhost" || location.hostname === "127.0.0.1";
    if (isLocalhost) {
      try {
        const proto = location.protocol === "https:" ? "wss" : "ws";
        socket = new WebSocket(`${proto}://${location.host}/ws`);
        socket.onmessage = (msg) => {
          try {
            const ev = JSON.parse(msg.data);
            if (ev && ev.order && ev.order.id) sub500Alarmed.delete(ev.order.id);
            applyCloudEvent(ev);
          } catch { /* ignore */ }
        };
        socket.onclose = () => { socket = null; };
      } catch { /* ignore */ }
    }
  }
  if (el) {
    el.textContent = "● Canlı Radar & Bulut Aktif";
    el.style.color = "#3AF1D7";
  }
  if (poll) clearInterval(poll);
  poll = setInterval(syncState, 2000);
}

async function syncState() {
  const ok = await fetchDirectSupabaseState();
  if (!ok) {
    const local = localStorage.getItem("konumum.web.runtime");
    if (local) {
      try {
        const parsed = JSON.parse(local);
        if (Array.isArray(parsed.orders)) runtime.orders = filterActiveBoardOrders(parsed.orders);
        runtime.menuExtras = { ...runtime.menuExtras, ...parsed.menuExtras };
        runtime.menus = { ...(runtime.menus || {}), ...(parsed.menus || {}) };
        runtime.campaigns = parsed.campaigns || runtime.campaigns;
        runtime.profiles = { ...runtime.profiles, ...parsed.profiles };
      } catch { /* ignore */ }
    } else if (boardClearedAt === 0) {
      try {
        const fileData = await (await fetch("data/runtime.json?t=" + Date.now(), { cache: "no-store" })).json();
        if (fileData && Array.isArray(fileData.orders)) {
          runtime.orders = filterActiveBoardOrders(fileData.orders);
          runtime.menuExtras = { ...runtime.menuExtras, ...fileData.menuExtras };
          runtime.menus = { ...(runtime.menus || {}), ...(fileData.menus || {}) };
          runtime.campaigns = fileData.campaigns || runtime.campaigns;
          runtime.profiles = { ...runtime.profiles, ...fileData.profiles };
        }
      } catch { /* ignore */ }
    }
  }
  runtime.orders = filterActiveBoardOrders(runtime.orders);
  (runtime.orders || []).forEach((order) => {
    if (Number(order.meters) === 0 || order.atDoor) doorAlarm(order);
    else if (Number(order.meters) > 0 && Number(order.meters) < ALARM_THRESHOLD_M) approach500Alarm(order);
    if (order.status === "iletildi") ticketPing(order);
  });
  if (!session) return;
  if (tab === "home") {
    renderKds();
    renderLiveList();
    draw();
  }
  if (tab === "orders") renderOrders();
  if (tab === "hq") renderHq();
}

function renderTabs() {
  const items = [
    canKitchen() ? ["home", "Mutfak & Canlı Takip (KDS)"] : null,
    ["orders", "Gelen Siparişler"],
    canKitchen() ? ["menu", "Menü & Stok (86)"] : null,
    canManage() ? ["campaigns", "Kampanyalar"] : null,
    canManage() || canCash() ? ["reports", "Rapor & Hakediş"] : null,
    ["profile", "Restoran Profili"],
    ["legal", "Hukuk & KVKK"],
    isSuperAdmin() ? ["hq", "👑 Genel Merkez (Patron)"] : null
  ].filter(Boolean);

  $("tabs").innerHTML = items.map(([id, title]) => {
    const ico = id === "home" ? `<span class="ico">🍳</span>` : "";
    const on = id === tab;
    return `<button type="button" data-tab="${id}" class="${on ? "on" : ""}">${ico}${title}</button>`;
  }).join("") + `
    <button class="mute-btn" id="muteBtn" type="button" title="Tüm sesleri sessize al / aç">${soundMuted ? "🔇 Sessiz" : "🔊 Ses açık"}</button>
    <button class="logout on" id="logout" type="button" style="color:#FF4272;border-color:rgba(255,66,114,.95);background:rgba(255,66,114,.14);font-weight:800">Çıkış</button>
  `;
  [...$("tabs").querySelectorAll("button[data-tab]")].forEach((btn) => {
    btn.onclick = () => showTab(btn.dataset.tab);
  });
  paintMute();
  const muteBtn = $("muteBtn");
  if (muteBtn) muteBtn.onclick = () => {
    soundMuted = !soundMuted;
    localStorage.setItem("konumum.web.muted", soundMuted ? "1" : "0");
    paintMute();
  };
  const logoutBtn = $("logout");
  if (logoutBtn) logoutBtn.onclick = doLogout;
}

function showTab(id) {
  tab = id;
  renderTabs();
  const restaurantHome = id === "home";
  $("navPane").classList.toggle("hidden", !restaurantHome);
  ["orders", "menu", "campaigns", "reports", "profile", "legal", "hq"].forEach((name) => {
    const pane = $(name + "Pane");
    if (pane) pane.classList.toggle("hidden", name !== id);
  });
  if (restaurantHome) {
    renderKds();
    renderLiveList();
    draw();
    bindOps();
  }
  if (id === "orders") renderOrders();
  if (id === "menu") renderMenu();
  if (id === "campaigns") renderCampaigns();
  if (id === "reports") renderReports();
  if (id === "profile") renderProfile();
  if (id === "legal") renderLegal();
  if (id === "hq") renderHq();
}

function statusRail(status, cancelReason) {
  if (status === "iptal") return `<span class="st bad">İptal Edildi${cancelReason ? " · " + esc(cancelReason) : ""}</span>`;
  return STATUS_STEPS.map((step) => {
    const on = status === step || (step === "yolda" && ["kapıda", "kapida"].includes(status));
    const done = STATUS_STEPS.indexOf(step) < STATUS_STEPS.indexOf(status === "kapıda" || status === "kapida" ? "yolda" : status);
    return `<span class="st ${on ? "on" : done ? "done" : ""}">${STATUS_LABEL[step]}</span>`;
  }).join("");
}

function orderActions(order) {
  const status = order.status;
  const slip = canCash() ? `<button class="go" data-print="${esc(order.id)}">Adisyon Yazdır</button>` : "";
  if (status === "iletildi") {
    return `<div class="act" style="flex-wrap:wrap">
      <button class="go" data-st="kabul" data-oid="${esc(order.id)}">Mutfağa Al</button>
      <select data-rejsel="${esc(order.id)}" style="background:#0d1322;color:#FF4272;border:1px solid rgba(255,66,114,.55);border-radius:8px;padding:4px 6px;font-size:11px;font-weight:700">
        <option value="Yoğunluk nedeniyle reddedildi">Red: Yoğunluk</option>
        <option value="Ürün / malzeme tükendi (86)">Red: Ürün Tükendi</option>
        <option value="Şube kapanış saatinde">Red: Kapanış Saati</option>
      </select>
      <button class="stop" data-st="iptal" data-oid="${esc(order.id)}">Reddet</button>
    </div>`;
  }
  if (status === "kabul") {
    return `<div class="act"><button class="ok" data-st="hazir" data-oid="${esc(order.id)}">Paket Hazır</button>${slip}</div>`;
  }
  if (["hazir", "yolda", "kapıda", "kapida"].includes(status)) {
    return `<div class="act">${slip}<button class="ok" data-st="teslim" data-oid="${esc(order.id)}">Camdan Teslim</button></div>`;
  }
  if (status === "teslim") return `<div class="act">${slip}</div>`;
  return "";
}

async function setOrderStatus(id, status, prep, cancelReason) {
  const row = (runtime.orders || []).find((o) => o.id === id);
  if (row) {
    row.status = status;
    if (prep) row.prepMinutes = Number(prep);
    if (cancelReason) row.cancelReason = cancelReason;
  }
  localStorage.setItem("konumum.web.runtime", JSON.stringify(runtime));
  if (sbClient) {
    try {
      const patch = {
        order_status: status,
        updated_at: new Date().toISOString()
      };
      if (prep) patch.prep_minutes = Number(prep);
      if (cancelReason) patch.cancel_reason = cancelReason;
      await sbClient.from("orders").update(patch).eq("id", id);
      await sbClient.from("live_tracking").update({
        order_status: status,
        updated_at: new Date().toISOString()
      }).eq("order_id", id);
    } catch { /* ignore */ }
  }
  await persist();
  if (tab === "orders") renderOrders();
  if (tab === "home") {
    renderKds();
    renderLiveList();
    draw();
  }
}

function bindOrderActions(root) {
  [...root.querySelectorAll("[data-st]")].forEach((btn) => {
    btn.onclick = () => {
      const oid = btn.dataset.oid;
      const st = btn.dataset.st;
      let reason = "";
      if (st === "iptal") {
        const sel = root.querySelector(`[data-rejsel="${oid}"]`);
        reason = sel ? sel.value : "Yoğunluk nedeniyle reddedildi";
      }
      setOrderStatus(oid, st, btn.dataset.prep, reason);
    };
  });
  [...root.querySelectorAll("[data-print]")].forEach((btn) => {
    btn.onclick = () => printSlip(btn.dataset.print);
  });
}

function driveNote(order) {
  if (["teslim", "iptal"].includes(order.status)) return "";
  if (order.atDoor || Number(order.meters) === 0 || ["kapıda", "kapida"].includes(order.status)) {
    return "<div class='note' style='color:#FF4272;font-weight:800;margin-top:4px'>🚨 KAPIDA · 0 m · Camdan teslim</div>";
  }
  return "";
}

function ticketCard(order, isNew) {
  const p = proximity(order.meters);
  const open = !["teslim", "iptal"].includes(order.status);
  const atDoor = Number(order.meters) === 0 || order.atDoor || ["kapıda", "kapida"].includes(order.status);
  const col = atDoor ? "#FF4272" : p.color;
  return `<div class="ticket ${isNew ? "new" : ""}" style="${atDoor && open ? "border-color:#FF4272;box-shadow:0 0 16px rgba(255,66,114,.3)" : ""}">
    <div style="display:flex;justify-content:space-between;align-items:center;gap:6px">
      <div class="plate" style="background:${open ? col : "#3AF1D7"}">${esc(order.plate)}</div>
      <span class="tag" style="cursor:default">₺${Number(order.total || 0)}</span>
    </div>
    <div class="note" style="margin-top:8px;font-weight:700;color:#fff">${esc(order.driverName || order.customer)}</div>
    <div class="note" style="margin-top:2px">${esc(order.items)}</div>
    <div class="note" style="font-size:11px;margin-top:4px;opacity:.75">${esc(order.payment || "Kart")}</div>
    ${open ? `<div class="note" style="color:${col};font-weight:800;font-size:13px;margin-top:6px">📍 ${esc(formatDistanceEta(order.meters))}</div>` : ""}
    ${driveNote(order)}
    ${orderActions(order)}
  </div>`;
}

function renderKds() {
  const board = $("kdsBoard");
  if (!board) return;
  const rows = (runtime.orders || []).filter((o) => o.restaurantId === session.id);
  const newCount = rows.filter((o) => o.status === "iletildi").length;
  const prepCount = rows.filter((o) => o.status === "kabul").length;
  const doorCount = rows.filter((o) => !["teslim", "iptal"].includes(o.status) && (Number(o.meters) === 0 || o.atDoor || ["kapıda", "kapida"].includes(o.status))).length;
  const doneCount = rows.filter((o) => o.status === "teslim").length;

  const summary = $("kdsSummary");
  if (summary) {
    summary.innerHTML = `
      <div class="metric"><span class="note">Yeni Sipariş</span><b style="color:#3AF1D7">${newCount}</b></div>
      <div class="metric"><span class="note">Hazırlanıyor</span><b style="color:#FFD129">${prepCount}</b></div>
      <div class="metric"><span class="note">Kapıda Bekleyen (0 m)</span><b style="color:#FF4272">${doorCount}</b></div>
      <div class="metric"><span class="note">Teslim Edilen</span><b style="color:#38F27A">${doneCount}</b></div>
    `;
  }

  const col = (key, title, match) => {
    const items = rows.filter(match);
    return `<div class="kds-col"><h3>${title} · ${items.length}</h3>${items.map((o) => ticketCard(o, o.status === "iletildi")).join("") || "<p class='note'>Boş</p>"}</div>`;
  };
  board.innerHTML =
    col("yeni", "Yeni", (o) => o.status === "iletildi") +
    col("prep", "Hazırlanıyor", (o) => o.status === "kabul") +
    col("thru", "Yolda / Kapıda", (o) => ["hazir", "yolda", "kapıda", "kapida"].includes(o.status)) +
    col("done", "Teslim Edildi", (o) => o.status === "teslim");
  bindOrderActions(board);
}

function bindOps() {
  if (!session) return;
  const p = profileOf(session.id);
  const pick = $("branchPick");
  if (pick) {
    pick.classList.add("hidden");
    pick.innerHTML = "";
  }
  const openBtn = $("openToggle");
  if (openBtn) {
    const st = storeOpenState(session.id);
    if (st.open) {
      openBtn.textContent = st.withinHours ? `🟢 Mağaza Açık (${st.hours})` : `🟡 Açık · Mesai Dışı (${st.hours})`;
      openBtn.style.borderColor = st.withinHours ? "rgba(56,242,122,.85)" : "rgba(255,209,41,.85)";
      openBtn.style.color = st.withinHours ? "#38F27A" : "#FFD129";
      openBtn.style.background = st.withinHours ? "rgba(56,242,122,.12)" : "rgba(255,209,41,.12)";
    } else {
      openBtn.textContent = `🔴 Mağaza Kapalı (${st.hours})`;
      openBtn.style.borderColor = "rgba(255,66,114,.95)";
      openBtn.style.color = "#FF4272";
      openBtn.style.background = "rgba(255,66,114,.14)";
    }
    openBtn.classList.remove("on");
    openBtn.onclick = async () => {
      runtime.profiles[session.id] = Object.assign({}, profileOf(session.id), { open: !st.open, paused: false });
      await persist();
      bindOps();
      updateHeaderWho();
    };
  }
  const busyBtn = $("busyToggle");
  if (busyBtn) {
    const busy = p.busy || "mid";
    busyBtn.textContent = "Yoğunluk · " + BUSY_LABEL[busy];
    busyBtn.onclick = async () => {
      const next = BUSY_CYCLE[(BUSY_CYCLE.indexOf(busy) + 1) % BUSY_CYCLE.length];
      runtime.profiles[session.id] = Object.assign({}, profileOf(session.id), { busy: next });
      await persist();
      bindOps();
    };
  }
  const clearDoneBtn = $("clearCompletedBtn");
  if (clearDoneBtn) {
    clearDoneBtn.onclick = () => clearOrders("completed");
  }
  const clearAllBtn = $("clearBoardBtn");
  if (clearAllBtn) {
    clearAllBtn.onclick = () => clearOrders("all");
  }
}

async function clearOrders(mode = "completed") {
  if (!session) return;
  if (mode === "all") {
    (runtime.orders || []).forEach((o) => {
      if (o.restaurantId === session.id && o.id) dismissedOrderIds.add(String(o.id));
    });
    runtime.orders = (runtime.orders || []).filter((o) => o.restaurantId !== session.id);
    alarmed.clear();
    sub500Alarmed.clear();
  } else {
    (runtime.orders || []).forEach((o) => {
      if (o.restaurantId === session.id && ["teslim", "iptal"].includes(o.status) && o.id) {
        dismissedOrderIds.add(String(o.id));
      }
    });
    runtime.orders = (runtime.orders || []).filter((o) =>
      o.restaurantId !== session.id || !["teslim", "iptal"].includes(o.status)
    );
  }
  boardClearedAt = Date.now();
  localStorage.setItem("konumum.web.clearedAt", String(boardClearedAt));
  localStorage.setItem("konumum.web.dismissed", JSON.stringify([...dismissedOrderIds]));
  localStorage.setItem("konumum.web.runtime", JSON.stringify(runtime));
  try {
    await fetch("/api/orders/clear", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ restaurantId: session.id, mode })
    });
  } catch { /* ignore */ }
  if (sbClient) {
    try {
      if (mode === "all") {
        await sbClient.from("live_tracking").delete().eq("restaurant_id", session.id);
        await sbClient.from("orders").delete().eq("restaurant_id", session.id);
      } else {
        await sbClient.from("live_tracking").delete().eq("restaurant_id", session.id).in("order_status", ["teslim", "iptal"]);
        await sbClient.from("orders").delete().eq("restaurant_id", session.id).in("order_status", ["teslim", "iptal"]);
      }
    } catch { /* ignore */ }
  }
  await persist(true);
  if (tab === "home") {
    renderKds();
    renderLiveList();
    draw();
  }
  if (tab === "orders") renderOrders();
  if (tab === "reports") renderReports();
}

function renderLiveList() {
  const rows = liveOrders();
  const list = $("liveList");
  if (!list) return;
  list.innerHTML = rows.map((order) => {
    const p = proximity(order.meters);
    const atDoor = Number(order.meters) === 0 || order.atDoor || ["kapıda", "kapida"].includes(order.status);
    const col = atDoor ? "#FF4272" : p.color;
    return `<div class="row">
      <div>
        <div class="plate" style="background:${col}">${esc(order.plate)}</div>
        <div class="note" style="margin-top:4px">${esc(order.driverName || order.customer)} · ${esc(order.items)}</div>
        ${driveNote(order)}
      </div>
      <div style="color:${col};font-weight:800;text-align:right">📍 ${esc(formatDistanceEta(order.meters))}</div>
    </div>`;
  }).join("") || "<p class='note' style='margin-top:10px'>Şu an yaklaşan aktif araç yok. Mobil uygulamadan sipariş verildiğinde burada canlı görünür.</p>";
}

function draw() {
  const c = $("map");
  if (!c) return;
  const ctx = c.getContext("2d");
  const w = c.width, h = c.height;
  ctx.fillStyle = "#070b12";
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = "rgba(255,255,255,.06)";
  ctx.lineWidth = 1;
  for (let x = 0; x < w; x += 28) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke(); }
  for (let y = 0; y < h; y += 28) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(w * 0.1, h * 0.84);
  ctx.quadraticCurveTo(w * 0.46, h * 0.62, w * 0.82, h * 0.18);
  ctx.strokeStyle = "rgba(58,241,215,.22)";
  ctx.lineWidth = 16;
  ctx.stroke();
  ctx.strokeStyle = "#3AF1D7";
  ctx.lineWidth = 4;
  ctx.stroke();
  ctx.fillStyle = "#FF4272";
  ctx.beginPath();
  ctx.arc(w * 0.82, h * 0.16, 9, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.font = "700 11px sans-serif";
  ctx.fillText("Camdan Teslim (0 m)", w * 0.82 - 58, h * 0.16 - 14);

  liveOrders().forEach((order, index) => {
    const m = Math.max(0, Math.min(START_M, Number(order.meters ?? START_M)));
    const t = 1 - m / START_M;
    const x = w * (0.1 + (0.82 - 0.1) * t);
    const y = h * (0.84 + (0.18 - 0.84) * t) + (index - 1) * 10;
    const p = proximity(order.meters);
    ctx.fillStyle = p.color;
    ctx.shadowColor = p.color;
    ctx.shadowBlur = 16;
    ctx.fillRect(x - 11, y - 7, 22, 14);
    ctx.shadowBlur = 0;
    const label = order.plate;
    ctx.font = "800 11px ui-monospace, Menlo, monospace";
    const tw = ctx.measureText(label).width + 14;
    ctx.fillStyle = p.color;
    ctx.fillRect(x - tw / 2, y - 26, tw, 16);
    ctx.fillStyle = "#0B0F19";
    ctx.fillText(label, x - tw / 2 + 7, y - 14);
  });
}

function renderOrders() {
  const allRows = (runtime.orders || []).filter((o) => o.restaurantId === session.id);
  const rows = allRows.filter((o) => {
    if (orderFilter === "active") return !["teslim", "iptal"].includes(o.status);
    if (orderFilter === "door") return !["teslim", "iptal"].includes(o.status) && (Number(o.meters) === 0 || o.atDoor || ["kapıda", "kapida"].includes(o.status));
    if (orderFilter === "done") return o.status === "teslim";
    if (orderFilter === "cancel") return o.status === "iptal";
    return true;
  });

  const filters = [
    ["all", `Tümü (${allRows.length})`],
    ["active", `Aktif (${allRows.filter((o) => !["teslim", "iptal"].includes(o.status)).length})`],
    ["door", `Kapıda 0 m (${allRows.filter((o) => !["teslim", "iptal"].includes(o.status) && (Number(o.meters) === 0 || o.atDoor)).length})`],
    ["done", `Teslim (${allRows.filter((o) => o.status === "teslim").length})`],
    ["cancel", `İptal (${allRows.filter((o) => o.status === "iptal").length})`]
  ];

  $("ordersPane").innerHTML = `<div class="card">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;margin-bottom:12px">
      <h2 style="margin:0">Gelen Araç Siparişleri</h2>
      <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
        <div class="chips" style="margin:0">
          ${filters.map(([k, label]) => `<button class="chip ${orderFilter === k ? "on" : ""}" data-of="${k}">${label}</button>`).join("")}
        </div>
        <button class="chip" id="ordClearDone" type="button" style="border-color:rgba(58,241,215,.55);color:#3AF1D7">Tamamlananları Temizle</button>
        <button class="chip" id="ordClearAll" type="button" style="border-color:rgba(255,66,114,.75);color:#FF4272">Tahtayı Temizle</button>
      </div>
    </div>
    ${rows.map((o) => {
      const p = proximity(o.meters);
      const open = !["teslim", "iptal"].includes(o.status);
      return `<div class="row">
        <div>
          <span class="plate" style="background:${open ? p.color : "#3AF1D7"}">${esc(o.plate)}</span>
          <div class="note" style="margin-top:6px;color:#fff;font-weight:700">${esc(o.driverName || o.customer)} · ₺${Number(o.total || 0)} (${esc(o.payment)})</div>
          <div class="note">${esc(o.items)}</div>
          ${open ? `<div class="note" style="color:${p.color};font-weight:800;margin-top:4px">📍 ${esc(formatDistanceEta(o.meters))}</div>` : ""}
          ${driveNote(o)}
          <div class="status-rail">${statusRail(o.status, o.cancelReason)}</div>
          ${orderActions(o)}
        </div>
        <div style="color:${open ? p.color : "#3AF1D7"};font-weight:800">${STATUS_LABEL[o.status] || o.status}</div>
      </div>`;
    }).join("") || "<p class='note'>Bu filtrede sipariş bulunmuyor.</p>"}
  </div>`;

  [...$("ordersPane").querySelectorAll("[data-of]")].forEach((btn) => {
    btn.onclick = () => {
      orderFilter = btn.dataset.of;
      renderOrders();
    };
  });
  const ordClearDone = $("ordClearDone");
  if (ordClearDone) ordClearDone.onclick = () => clearOrders("completed");
  const ordClearAll = $("ordClearAll");
  if (ordClearAll) ordClearAll.onclick = () => clearOrders("all");
  bindOrderActions($("ordersPane"));
}

function renderMenu() {
  const dishes = menuOf(session);
  $("menuPane").innerHTML = `<div class="card">
    <h2>Menü & Stok Yönetimi (86)</h2>
    <p class="note">Burada yapılan kategori, fiyat, varyasyon ve 86 (Tükendi) değişiklikleri anında mobil müşteri uygulamasında güncellenir.</p>
    <div id="dishList">${dishes.map((d, i) =>
      `<div class="menu-card">
        <div class="dish">
          <div class="dish-photo" style="background:${esc(d.photoBg || "#1a2433")}">${esc(d.photo || "🍽️")}</div>
          <div class="dish-copy">
            <b>${esc(d.name)}</b>
            <div class="kcal">${esc(d.category || guessCat(d.name))} · ${d.kcal || 0} kcal · stok ${d.stock ?? 99} · ${(d.allergens || []).join(", ") || "alerjen yok"}</div>
            <div class="tags">${(dishVars(d)).map((v) => `<span class="tag">${esc(v.name)}${v.priceDelta ? " +₺" + v.priceDelta : ""}</span>`).join("")}</div>
            ${d.soldOut || Number(d.stock ?? 99) <= 0 ? "<span class='sold-badge'>Tükendi (86)</span>" : ""}
          </div>
          <div class="qty-row">
            <input class="price" data-i="${i}" type="number" value="${d.price}" />
            <button class="tiny" data-i="${i}">Sil</button>
          </div>
        </div>
        <div class="emoji-pick">${PHOTOS.map((p) =>
          `<button data-photo="${i}" data-p="${p}" class="${d.photo === p ? "on" : ""}">${p}</button>`
        ).join("")}</div>
        <div class="grid2">
          <div><label>KATEGORİ</label>
            <select data-cat="${i}">${CATS.map((c) => `<option ${(d.category || guessCat(d.name)) === c ? "selected" : ""}>${c}</option>`).join("")}</select></div>
          <div><label>STOK ADEDİ</label><input data-stock="${i}" type="number" value="${d.stock ?? 99}" /></div>
          <div><label>KALORİ (KCAL)</label><input data-kcal="${i}" type="number" value="${d.kcal || 0}" /></div>
          <div><label>VARYASYON / MODIFIER (ad:fiyat)</label>
            <input data-vars="${i}" value="${esc(dishVars(d).map((v) => v.name + ":" + (v.priceDelta || 0)).join(", "))}" /></div>
        </div>
        <div class="tags" style="margin-top:8px">
          ${ALLERGENS.map((a) =>
            `<button class="tag ${(d.allergens || []).includes(a) ? "on" : ""}" data-al="${i}" data-a="${esc(a)}">${esc(a)}</button>`
          ).join("")}
        </div>
        <label class="toggle" style="margin-top:8px"><input type="checkbox" data-sold="${i}" ${d.soldOut ? "checked" : ""} /> 86 · Tükendi olarak işaretle</label>
      </div>`
    ).join("")}</div>
    <h3 style="margin-top:20px">Yeni Ürün Ekle</h3>
    <div class="grid2" style="margin-top:8px">
      <div><label>YEMEK ADI</label><input id="dishName" placeholder="Yeni ürün adı" /></div>
      <div><label>FİYAT ₺</label><input id="dishPrice" type="number" placeholder="180" /></div>
      <div><label>KALORİ</label><input id="dishKcal" type="number" placeholder="450" /></div>
      <div><label>STOK</label><input id="dishStock" type="number" placeholder="40" /></div>
      <div><label>KATEGORİ</label><select id="dishCat">${CATS.map((c) => `<option>${c}</option>`).join("")}</select></div>
      <div><label>İKON / GÖRSEL</label><input id="dishPhoto" maxlength="4" placeholder="🍔" /></div>
    </div>
    <div class="emoji-pick" id="newPhoto">${PHOTOS.map((p) => `<button data-newp="${p}">${p}</button>`).join("")}</div>
    <button class="primary" id="addDish">Menüye Ekle ve Mobil Uygulamaya Yayınla</button>
    <div class="ok" id="menuMsg"></div>
  </div>`;
  $("addDish").onclick = addDish;
  [...$("newPhoto").querySelectorAll("button")].forEach((btn) => {
    btn.onclick = () => { $("dishPhoto").value = btn.dataset.newp; };
  });
  [...$("dishList").querySelectorAll(".tiny")].forEach((btn) => {
    btn.onclick = () => removeDish(Number(btn.dataset.i));
  });
  [...$("dishList").querySelectorAll("input.price")].forEach((input) => {
    input.onchange = () => patchDish(Number(input.dataset.i), { price: Number(input.value) });
  });
  [...$("dishList").querySelectorAll("[data-kcal]")].forEach((input) => {
    input.onchange = () => patchDish(Number(input.dataset.kcal), { kcal: Number(input.value) });
  });
  [...$("dishList").querySelectorAll("[data-stock]")].forEach((input) => {
    input.onchange = () => {
      const stock = Number(input.value);
      patchDish(Number(input.dataset.stock), { stock, soldOut: stock <= 0 });
    };
  });
  [...$("dishList").querySelectorAll("[data-cat]")].forEach((input) => {
    input.onchange = () => patchDish(Number(input.dataset.cat), { category: input.value });
  });
  [...$("dishList").querySelectorAll("[data-vars]")].forEach((input) => {
    input.onchange = () => patchDish(Number(input.dataset.vars), { variations: parseVars(input.value) });
  });
  [...$("dishList").querySelectorAll("[data-photo]")].forEach((btn) => {
    btn.onclick = () => patchDish(Number(btn.dataset.photo), { photo: btn.dataset.p });
  });
  [...$("dishList").querySelectorAll("[data-al]")].forEach((btn) => {
    btn.onclick = () => toggleAllergen(Number(btn.dataset.al), btn.dataset.a);
  });
  [...$("dishList").querySelectorAll("[data-sold]")].forEach((input) => {
    input.onchange = () => patchDish(Number(input.dataset.sold), { soldOut: input.checked });
  });
}

function parseVars(text) {
  return String(text).split(",").map((part, i) => {
    const [name, delta] = part.split(":").map((s) => s.trim());
    if (!name) return null;
    return { id: "v" + i, name, priceDelta: Number(delta || 0) };
  }).filter(Boolean);
}

function patchDish(index, patch) {
  const dishes = menuOf(session).map((row, i) => i === index ? { ...row, ...patch } : row);
  runtime.menus = runtime.menus || {};
  runtime.menus[session.id] = dishes;
  publishMenu();
  renderMenu();
}

function toggleAllergen(index, name) {
  const dishes = menuOf(session);
  const row = dishes[index];
  const set = new Set(row.allergens || []);
  if (set.has(name)) set.delete(name);
  else set.add(name);
  patchDish(index, { allergens: [...set] });
}

function addDish() {
  const name = $("dishName").value.trim();
  const price = Number($("dishPrice").value);
  if (!name || !price) return;
  const current = menuOf(session);
  const newItem = {
    id: "web-" + Date.now(),
    name,
    price,
    photo: $("dishPhoto").value.trim() || "🍽️",
    photoBg: "#1a2433",
    kcal: Number($("dishKcal").value || 0),
    stock: Number($("dishStock")?.value || 40),
    category: $("dishCat")?.value || "Ana yemek",
    allergens: [],
    variations: [{ id: "std", name: "Standart", priceDelta: 0 }],
    soldOut: false
  };
  runtime.menus = runtime.menus || {};
  runtime.menus[session.id] = [...current, newItem];
  const extra = extrasFor(session.id);
  extra.push(newItem);
  runtime.menuExtras[session.id] = extra;
  publishMenu();
  renderMenu();
  const msg = $("menuMsg");
  if (msg) msg.textContent = "Yeni ürün menüye eklendi ve mobil uygulamaya yayınlandı.";
}

function removeDish(index) {
  const dishes = menuOf(session).filter((_, i) => i !== index);
  runtime.menus = runtime.menus || {};
  runtime.menus[session.id] = dishes;
  publishMenu();
  renderMenu();
}

async function publishMenu() {
  const items = menuOf(session);
  runtime.menus = runtime.menus || {};
  runtime.menus[session.id] = items;
  await persist();
}

function renderCampaigns() {
  if (!session) return;
  const myCampaigns = (runtime.campaigns || []).filter((c) => c.restaurantId === session.id);
  $("campaignsPane").innerHTML = `<div class="card">
    <h2>Restoran Kampanyaları · ${esc(session.branchTitle)}</h2>
    <p class="note">Yalnızca kendi işletmenize ait kampanyaları görür ve yönetirsiniz. Eklediğiniz kampanyalar mobil uygulamada yayınlanır.</p>
    ${myCampaigns.map((c) =>
      `<div class="row" style="align-items:center">
        <div>
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
            <b>${esc(c.title)}</b>
            <span class="tag on" style="cursor:default;font-family:ui-monospace,Menlo,monospace">${esc(c.code || "KONUMUM20")} · %${Number(c.discountPercent || 20)}</span>
          </div>
          <div class="note">${esc(c.detail)}</div>
        </div>
        <div class="act" style="margin:0">
          <button class="${c.active ? "ok" : "go"}" data-ctog="${esc(c.id)}">${c.active ? "Aktif" : "Pasif"}</button>
          <button class="stop" data-cdel="${esc(c.id)}">Sil</button>
        </div>
      </div>`
    ).join("") || "<p class='note'>İşletmenize ait henüz bir kampanya yok.</p>"}
    <div class="grid2" style="margin-top:14px">
      <div><label>KAMPANYA BAŞLIĞI *</label><input id="campTitle" placeholder="Örn: Araçta Teslim %20 İndirim" /></div>
      <div><label>KUPON KODU (MOBİL ÖDEMEDE GEÇERLİ)</label><input id="campCode" placeholder="Örn: ATAKUM20 (Varsayılan: KONUMUM20)" style="text-transform:uppercase;font-family:ui-monospace,Menlo,monospace" /></div>
      <div><label>İNDİRİM ORANI (%)</label><input id="campPct" type="number" min="5" max="75" value="20" placeholder="20" /></div>
      <div><label>KAMPANYA DETAYI</label><input id="campDetail" placeholder="Örn: Tüm menülerde araç camından teslimde geçerli" /></div>
    </div>
    <button class="primary" id="addCamp">Kampanya Ekle ve Yayınla</button>
  </div>`;

  const add = $("addCamp");
  if (add) add.onclick = async () => {
    const title = $("campTitle").value.trim();
    const rawCode = String($("campCode")?.value || "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
    const code = rawCode || "KONUMUM20";
    const discountPercent = Math.max(5, Math.min(75, Number($("campPct")?.value || 20)));
    const detail = $("campDetail").value.trim() || `${code} koduyla %${discountPercent} indirim`;
    if (!title) return;
    const camp = {
      id: "c-" + Date.now(),
      restaurantId: session.id,
      branchTitle: session.branchTitle,
      title,
      detail,
      code,
      discountPercent,
      active: true
    };
    runtime.campaigns = runtime.campaigns || [];
    runtime.campaigns.unshift(camp);
    await persist();
    renderCampaigns();
  };

  [...$("campaignsPane").querySelectorAll("[data-ctog]")].forEach((btn) => {
    btn.onclick = async () => {
      const cid = btn.dataset.ctog;
      const target = (runtime.campaigns || []).find((c) => c.id === cid && c.restaurantId === session.id);
      if (target) {
        target.active = !target.active;
        await persist();
        renderCampaigns();
      }
    };
  });

  [...$("campaignsPane").querySelectorAll("[data-cdel]")].forEach((btn) => {
    btn.onclick = async () => {
      const cid = btn.dataset.cdel;
      runtime.campaigns = (runtime.campaigns || []).filter((c) => !(c.id === cid && c.restaurantId === session.id));
      await persist();
      renderCampaigns();
    };
  });
}

function renderProfile() {
  const p = Object.assign({}, session, runtime.profiles[session.id] || {});
  const rawHours = String(p.hours || session.hours || "10:00-23:00");
  const hm = /^(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})$/.exec(rawHours.trim());
  const openTime = hm ? hm[1].padStart(5, "0") : "10:00";
  const closeTime = hm ? hm[2].padStart(5, "0") : "23:00";
  const st = storeOpenState(session.id);
  $("profilePane").innerHTML = `<div class="card"><h2>Restoran & Şube İşletme Profili</h2>
    <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;padding:12px 14px;margin-bottom:14px;border-radius:14px;background:rgba(255,255,255,.04);border:1px solid ${st.effectiveOpen ? "rgba(56,242,122,.45)" : "rgba(255,66,114,.55)"}">
      <div>
        <div style="font-weight:800;font-size:15px;color:${st.effectiveOpen ? "#38F27A" : "#FF4272"}">
          ${st.effectiveOpen ? "🟢 Mağaza Şu Anda Siparişe AÇIK" : "🔴 Mağaza Şu Anda Siparişe KAPALI"}
        </div>
        <div class="note" style="margin-top:4px">
          Manuel Durum: <b>${st.open ? "Açık" : "Kapalı"}</b> · Çalışma Saatleri: <b>${esc(st.hours)}</b> (${st.withinHours ? "Mesai saatleri içinde" : "Mesai saatleri dışında"}) · Yoğunluk: <b>${esc(BUSY_LABEL[st.busy])}</b>
        </div>
      </div>
      <div style="display:flex;gap:8px;align-items:center">
        <button type="button" class="ghost" id="profToggleOpen" style="width:auto;margin:0;padding:0 14px;height:38px;border-color:${st.open ? "rgba(255,66,114,.85)" : "rgba(56,242,122,.85)"};color:${st.open ? "#FF4272" : "#38F27A"}">
          ${st.open ? "Mağazayı Kapat" : "Mağazayı Aç"}
        </button>
      </div>
    </div>
    <div class="grid2">
      <div><label>RESMİ TİCARİ UNVAN (FATURA / HAKEDİŞ)</label><input id="pTitle" value="${esc(p.officialTitle || "")}" placeholder="Örn: Lezzet Gıda İşletmeleri A.Ş." /></div>
      <div><label>ŞUBE ADI</label><input id="pBranch" value="${esc(p.branchTitle || "")}" /></div>
      <div><label>VERGİ DAİRESİ</label><input id="pTaxOffice" value="${esc(p.taxOffice || "")}" placeholder="Örn: 19 Mayıs V.D. / Gaziler V.D." /></div>
      <div><label>VERGİ KİMLİK NO (VKN 10 / TCKN 11 HANE)</label><input id="pTax" maxlength="11" inputmode="numeric" value="${esc(p.taxNumber || "")}" placeholder="10 haneli VKN veya 11 haneli TCKN" /></div>
      <div style="grid-column:1 / -1"><label>HAKEDİŞ BANKA IBAN (TR · 26 KARAKTER)</label><input id="pIban" maxlength="32" value="${esc(formatTrIban(p.iban || ""))}" placeholder="TR00 0000 0000 0000 0000 0000 00" style="font-family:ui-monospace,Menlo,monospace;letter-spacing:.6px" /></div>
      <div><label>KURUMSAL E-POSTA</label><input id="pEmail" value="${esc(p.email || "")}" /></div>
      <div><label>PANEL ŞİFRESİ</label><input id="pPass" type="password" value="${esc(p.password || "")}" /></div>
      <div><label>ŞUBE TELEFONU</label><input id="pPhone" value="${esc(p.phone || "")}" /></div>
      <div><label>AÇIK ADRES (TESLİM NOKTASI)</label><input id="pAddr" value="${esc(p.address || "")}" /></div>
      <div><label>MUTFAK KATEGORİSİ</label><input id="pCuisine" value="${esc(p.cuisine || session.cuisine || "")}" placeholder="Burger, Döner, Pizza" /></div>
      <div>
        <label>ÇALIŞMA SAATLERİ (AÇILIŞ – KAPANIŞ)</label>
        <div style="display:flex;gap:8px;align-items:center">
          <input id="pOpenTime" type="time" value="${esc(openTime)}" style="flex:1" />
          <span class="note">–</span>
          <input id="pCloseTime" type="time" value="${esc(closeTime)}" style="flex:1" />
          <input id="pHours" value="${esc(rawHours)}" placeholder="10:00-23:00" style="flex:1.2" />
        </div>
      </div>
      <div>
        <label>RESTORAN GPS KOORDİNATI (ENLEM / BOYLAM)</label>
        <div style="display:flex;gap:8px;align-items:center">
          <input id="pLat" type="number" step="0.00001" value="${esc(p.latitude ?? session.latitude ?? 41.3320)}" placeholder="41.3320" style="flex:1" />
          <input id="pLng" type="number" step="0.00001" value="${esc(p.longitude ?? session.longitude ?? 36.2730)}" placeholder="36.2730" style="flex:1" />
          <button type="button" class="ghost" id="btnUseMyLoc" style="width:auto;margin:0;padding:0 10px;height:40px;font-size:12px;border-color:rgba(58,241,215,.6);color:#3AF1D7">📍 Konumumu Al</button>
        </div>
      </div>
    </div>
    <h3 style="margin-top:18px">Restoran Logosu (Mobil Uygulama Vitrini)</h3>
    <p class="note">Bu logo mobil müşteri uygulamasındaki restoran seçim ekranında görünür.</p>
    <div class="logo-edit">
      <div class="logo" id="logoPreview" style="background:${esc(p.logoBg || session.logoBg || "#3AF1D7")};color:${esc(p.logoFg || session.logoFg || "#0B0F19")}">${esc(p.logoMark || session.logoMark || "M")}</div>
      <div class="grid2" style="flex:1">
        <div><label>KISALTMA / İŞARET</label><input id="pMark" maxlength="4" value="${esc(p.logoMark || session.logoMark || "")}" placeholder="M" /></div>
        <div><label>ZEMİN RENGİ</label><input id="pLogoBg" value="${esc(p.logoBg || session.logoBg || "#dc1420")}" /></div>
        <div><label>YAZI RENGİ</label><input id="pLogoFg" value="${esc(p.logoFg || session.logoFg || "#ffc70a")}" /></div>
      </div>
    </div>
    <button class="primary" id="saveProf">İşletme Bilgilerini Kaydet</button>
    <div class="ok" id="profMsg"></div>

    <div style="margin-top:26px;padding:16px;border-radius:14px;background:rgba(255,66,114,.06);border:1px solid rgba(255,66,114,.45)">
      <h3 style="margin:0 0 6px 0;color:#FF4272">Tehlikeli Bölge · Mağaza / İşletme Hesabını Kalıcı Olarak Sil</h3>
      <p class="note" style="margin:0 0 12px 0">
        6698 sayılı KVKK m.7 ve 6563 sayılı ETK kapsamında mağaza üyeliğinizi sonlandırabilirsiniz. Bu işlem mağaza profilinizi, menünüzü, kampanyalarınızı ve mobil uygulamadaki vitrin kaydınızı bulut sunucularımızdan <b>kalıcı olarak siler</b>.
      </p>
      <button type="button" class="ghost" id="btnShowDeleteStore" style="border-color:rgba(255,66,114,.85);color:#FF4272;font-weight:800">
        🗑️ Mağazamı ve İşletme Hesabımı Kalıcı Olarak Sil
      </button>
      <div id="deleteStoreConfirmBox" class="hidden" style="margin-top:12px;padding:14px;border-radius:12px;background:rgba(11,15,25,.85);border:1px solid rgba(255,66,114,.7)">
        <p style="margin:0 0 10px 0;font-size:13px;font-weight:700;color:#FF4272">
          ⚠️ DİKKAT: "${esc(p.branchTitle || session.branchTitle)}" mağazası, tüm menü ürünleri ve bulut kaydı kalıcı olarak silinecek ve mobil uygulamadan kaldırılacaktır. Onaylamak için aşağıya şube şifrenizi girin:
        </p>
        <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
          <input id="delStorePass" type="password" placeholder="Panel şifrenizi girin" style="flex:1;min-width:200px;margin:0" />
          <button type="button" class="stop" id="btnConfirmDeleteStore" style="width:auto;margin:0;padding:0 16px;height:42px;background:#FF4272;color:#0B0F19;font-weight:800;border:none;border-radius:10px;cursor:pointer">
            Kalıcı Olarak Sil ve Kapat
          </button>
          <button type="button" class="ghost" id="btnCancelDeleteStore" style="width:auto;margin:0;padding:0 14px;height:42px">
            Vazgeç
          </button>
        </div>
        <div class="err" id="delStoreErr" style="margin-top:8px"></div>
      </div>
    </div>
  </div>`;
  $("saveProf").onclick = saveProfile;
  if ($("pIban")) {
    $("pIban").oninput = (e) => {
      e.target.value = formatTrIban(e.target.value);
    };
  }
  if ($("pTax")) {
    $("pTax").oninput = (e) => {
      e.target.value = String(e.target.value || "").replace(/\D/g, "").slice(0, 11);
    };
  }
  if ($("btnShowDeleteStore")) {
    $("btnShowDeleteStore").onclick = () => {
      $("deleteStoreConfirmBox")?.classList.remove("hidden");
      $("delStorePass")?.focus();
    };
  }
  if ($("btnCancelDeleteStore")) {
    $("btnCancelDeleteStore").onclick = () => {
      $("deleteStoreConfirmBox")?.classList.add("hidden");
      if ($("delStoreErr")) $("delStoreErr").textContent = "";
    };
  }
  if ($("btnConfirmDeleteStore")) {
    $("btnConfirmDeleteStore").onclick = deleteStorePermanently;
  }
  const syncHoursInputs = () => {
    const o = $("pOpenTime")?.value;
    const c = $("pCloseTime")?.value;
    if (o && c && $("pHours")) $("pHours").value = `${o}-${c}`;
  };
  if ($("pOpenTime")) $("pOpenTime").onchange = syncHoursInputs;
  if ($("pCloseTime")) $("pCloseTime").onchange = syncHoursInputs;
  if ($("btnUseMyLoc")) {
    $("btnUseMyLoc").onclick = () => {
      if (!navigator.geolocation) {
        $("profMsg").className = "err";
        $("profMsg").textContent = "Tarayıcınız konum özelliğini desteklemiyor.";
        return;
      }
      $("btnUseMyLoc").textContent = "⏳ Alınıyor...";
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          if ($("pLat")) $("pLat").value = pos.coords.latitude.toFixed(6);
          if ($("pLng")) $("pLng").value = pos.coords.longitude.toFixed(6);
          $("btnUseMyLoc").textContent = "✅ Konum Alındı";
          $("profMsg").className = "ok";
          $("profMsg").textContent = "Bulunduğunuz GPS koordinatı alındı. 'İşletme Bilgilerini Kaydet' butonuna basarak kaydedin.";
        },
        () => {
          $("btnUseMyLoc").textContent = "📍 Konumumu Al";
          $("profMsg").className = "err";
          $("profMsg").textContent = "Konum izni alınamadı. Tarayıcıdan konum izni verin veya koordinatı elle girin.";
        },
        { enableHighAccuracy: true, timeout: 10000 }
      );
    };
  }
  if ($("profToggleOpen")) {
    $("profToggleOpen").onclick = async () => {
      const cur = storeOpenState(session.id);
      runtime.profiles[session.id] = Object.assign({}, profileOf(session.id), { open: !cur.open, paused: false });
      await persist();
      bindOps();
      updateHeaderWho();
      renderProfile();
    };
  }
  const preview = () => {
    const box = $("logoPreview");
    if (!box) return;
    box.textContent = ($("pMark")?.value || "M").slice(0, 4);
    box.style.background = $("pLogoBg")?.value || "#3AF1D7";
    box.style.color = $("pLogoFg")?.value || "#0B0F19";
  };
  ["pMark", "pLogoBg", "pLogoFg"].forEach((id) => {
    const el = $(id);
    if (el) el.oninput = preview;
  });
}

async function saveProfile() {
  const latVal = parseFloat($("pLat")?.value);
  const lngVal = parseFloat($("pLng")?.value);
  const taxOfficeVal = String($("pTaxOffice")?.value || "").trim();
  const taxVal = String($("pTax")?.value || "").replace(/\D/g, "").trim();
  const ibanVal = formatTrIban($("pIban")?.value || "");
  if (taxVal && !isValidTaxOrTckn(taxVal)) {
    $("profMsg").className = "err";
    $("profMsg").textContent = "Vergi Kimlik No 10 haneli (VKN) veya 11 haneli (TCKN) olmalıdır.";
    return;
  }
  if (ibanVal && !isValidTrIban(ibanVal)) {
    $("profMsg").className = "err";
    $("profMsg").textContent = "Lütfen TR ile başlayan 26 haneli geçerli bir IBAN girin.";
    return;
  }
  const next = {
    officialTitle: $("pTitle").value.trim(),
    branchTitle: $("pBranch").value.trim(),
    email: $("pEmail").value.trim(),
    password: $("pPass").value,
    phone: $("pPhone").value.trim(),
    taxOffice: taxOfficeVal,
    taxNumber: taxVal,
    iban: ibanVal,
    address: $("pAddr").value.trim(),
    cuisine: $("pCuisine").value.trim(),
    hours: $("pHours").value.trim(),
    logoMark: $("pMark").value.trim(),
    logoBg: $("pLogoBg").value.trim(),
    logoFg: $("pLogoFg").value.trim(),
    latitude: Number.isFinite(latVal) ? latVal : (session.latitude ?? 41.3320),
    longitude: Number.isFinite(lngVal) ? lngVal : (session.longitude ?? 36.2730),
    updatedAt: new Date().toISOString()
  };
  runtime.profiles[session.id] = Object.assign({}, runtime.profiles[session.id] || {}, next);
  Object.assign(session, next);
  await persist();
  storeSession();
  updateHeaderWho();
  $("profMsg").className = "ok";
  $("profMsg").textContent = "İşletme, vergi ve IBAN bilgileri buluta kaydedildi.";
}

async function deleteStorePermanently() {
  if (!session) return;
  const errEl = $("delStoreErr");
  if (errEl) errEl.textContent = "";
  const enteredPass = String($("delStorePass")?.value || "").trim();
  const actualPass = String((runtime.profiles?.[session.id]?.password) || session.password || "").trim();
  if (!enteredPass || enteredPass !== actualPass) {
    if (errEl) errEl.textContent = "Girilen şifre hatalı. Mağazayı silmek için mevcut panel şifrenizi doğru girmelisiniz.";
    return;
  }
  const storeId = session.id;
  const storeEmail = String(session.email || "").trim().toLowerCase();
  const storeBayi = String(session.bayiKodu || "").trim().toLowerCase();

  if (runtime.profiles) delete runtime.profiles[storeId];
  if (runtime.menus) delete runtime.menus[storeId];
  if (runtime.menuExtras) delete runtime.menuExtras[storeId];
  if (Array.isArray(runtime.campaigns)) {
    runtime.campaigns = runtime.campaigns.filter((c) => c.restaurantId !== storeId);
  }
  if (Array.isArray(runtime.orders)) {
    runtime.orders = runtime.orders.filter((o) => o.restaurantId !== storeId);
  }

  const keysToDelete = [];
  if (storeEmail) keysToDelete.push(`__state_account:${storeEmail}`);
  if (storeBayi) keysToDelete.push(`__state_account:${storeBayi}`);

  for (const k of keysToDelete) {
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(k)}`, {
        method: "DELETE",
        headers: supabaseHeaders("return=minimal")
      });
    } catch { /* ignore */ }
  }
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/orders?restaurant_id=eq.${encodeURIComponent(storeId)}`, {
      method: "DELETE",
      headers: supabaseHeaders("return=minimal")
    });
    await fetch(`${SUPABASE_URL}/rest/v1/live_tracking?restaurant_id=eq.${encodeURIComponent(storeId)}`, {
      method: "DELETE",
      headers: supabaseHeaders("return=minimal")
    });
  } catch { /* ignore */ }

  await persist(true);
  doLogout();
  if ($("err")) {
    $("err").style.color = "#3AF1D7";
    $("err").textContent = "Mağaza hesabınız, menünüz ve bulut verileriniz kalıcı olarak silindi.";
  }
}

function todayKey(iso) {
  const raw = iso ? new Date(iso) : new Date();
  if (Number.isNaN(raw.getTime())) return new Date().toISOString().slice(0, 10);
  return raw.toISOString().slice(0, 10);
}

function renderReports() {
  if (!session) return;
  const day = new Date().toISOString().slice(0, 10);
  const rows = (runtime.orders || []).filter((o) => o.restaurantId === session.id);
  const paidAll = rows.filter((o) => o.status !== "iptal");
  const today = paidAll.filter((o) => todayKey(o.updatedAt) === day);
  const sourceRows = today.length ? today : paidAll;
  const gmv = sourceRows.reduce((sum, o) => sum + Number(o.total || 0), 0);
  const aov = sourceRows.length ? Math.round(gmv / sourceRows.length) : 0;
  const hours = {};
  sourceRows.forEach((o) => {
    const h = new Date(o.updatedAt || Date.now()).getHours();
    hours[h] = (hours[h] || 0) + 1;
  });
  const peak = Object.entries(hours).sort((a, b) => b[1] - a[1])[0];
  const fee = Math.round(gmv * COMMISSION);

  const byPayment = {};
  sourceRows.forEach((o) => {
    const k = o.payment || "Diğer";
    byPayment[k] = (byPayment[k] || 0) + Number(o.total || 0);
  });

  $("reportsPane").innerHTML = `<div class="card">
    <h2>Vardiya & Hakediş Raporu · ${esc(session.branchTitle)}</h2>
    <p class="note">İptal edilmeyen araç siparişleri üzerinden hesaplanır (Komisyon %${Math.round(COMMISSION * 100)}).</p>
    <div class="grid2" style="margin-top:12px">
      <div class="metric"><span class="note">Tamamlanan / Aktif Bilet</span><b>${sourceRows.length}</b></div>
      <div class="metric"><span class="note">Brüt Ciro (GMV)</span><b>₺${gmv}</b></div>
      <div class="metric"><span class="note">Ortalama Sepet (AOV)</span><b>₺${aov}</b></div>
      <div class="metric"><span class="note">Yoğun Saat</span><b>${peak ? peak[0] + ":00" : "—"}</b></div>
      <div class="metric"><span class="note">Platform Komisyonu (%${Math.round(COMMISSION * 100)})</span><b style="color:#FFD129">₺${fee}</b></div>
      <div class="metric"><span class="note">Restoran Net Hakediş (%${Math.round((1 - COMMISSION) * 100)})</span><b style="color:#3AF1D7">₺${gmv - fee}</b></div>
    </div>
    <div style="margin-top:16px;padding:12px 14px;border-radius:12px;background:rgba(58,241,215,.07);border:1px solid rgba(58,241,215,.28);font-size:12px;line-height:1.6">
      <b style="color:var(--neon)">🧾 Otomatik Komisyon Faturası &amp; Hakediş Aktarım Özeti:</b><br/>
      • <b>Komisyon e-Fatura / e-Arşiv No:</b> <span style="font-family:ui-monospace,Menlo,monospace">KY-${day.replace(/-/g, "")}-${esc((session.bayiKodu || session.id || "001").toUpperCase())}</span><br/>
      • <b>Tahsilat Dağılımı:</b> Brüt <b>₺${gmv}</b> tutar üzerinden <b>%${Math.round(COMMISSION * 100)} (₺${fee} KDV Dahil)</b> Konumum Yemek hizmet komisyonu otomatik mahsup edilir; kalan <b>₺${gmv - fee}</b> net hakediş kayıtlı TR IBAN hesabınıza aktarılır.
    </div>
    <h3 style="margin-top:20px">Yemek Kartı & Ödeme Dağılımı</h3>
    <div>
      ${Object.entries(byPayment).map(([method, sum]) =>
        `<div class="list-item"><span>${esc(method)}</span><b>₺${sum}</b></div>`
      ).join("") || "<p class='note'>Henüz ödeme kaydı yok.</p>"}
    </div>
  </div>`;
}

function renderHq() {
  const pane = $("hqPane");
  if (!pane || !session) return;
  const stores = allRestaurants();
  const allOrd = Array.isArray(runtime.orders) ? runtime.orders : [];
  const validOrd = allOrd.filter((o) => o && o.status !== "iptal" && !isSystemStateOrderRow(o));
  const totalGmv = validOrd.reduce((sum, o) => sum + Number(o.total || 0), 0);
  const totalCommission = Math.round(totalGmv * COMMISSION);
  const totalNetToRestaurants = totalGmv - totalCommission;
  const approachingCars = validOrd.filter((o) => o.status !== "teslim" && Number(o.meters) >= 0).length;
  const tickets = Array.isArray(runtime.supportTickets) ? runtime.supportTickets : [];

  const byStore = {};
  stores.forEach((s) => {
    byStore[s.id] = { store: s, count: 0, gmv: 0, fee: 0, net: 0 };
  });
  validOrd.forEach((o) => {
    const rid = o.restaurantId || "unknown";
    if (!byStore[rid]) {
      byStore[rid] = { store: { id: rid, branchTitle: rid, bayiKodu: rid }, count: 0, gmv: 0, fee: 0, net: 0 };
    }
    const amt = Number(o.total || 0);
    byStore[rid].count += 1;
    byStore[rid].gmv += amt;
    byStore[rid].fee = Math.round(byStore[rid].gmv * COMMISSION);
    byStore[rid].net = byStore[rid].gmv - byStore[rid].fee;
  });

  const dayCode = new Date().toISOString().slice(0, 10).replace(/-/g, "");

  pane.innerHTML = `<div class="card">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px">
      <div>
        <h2 style="margin:0;color:#FFD129">👑 Konumum Yemek · Türkiye Genel Merkez (Patron Paneli)</h2>
        <p class="note" style="margin:4px 0 0 0">Tüm üye restoranlar, Türkiye geneli canlı ciro, %${Math.round(COMMISSION * 100)} net komisyon kasası, otomatik e-fatura mutabakatı ve gelen destek talepleri.</p>
      </div>
      <span style="padding:6px 12px;border-radius:999px;background:rgba(56,242,122,.14);border:1px solid rgba(56,242,122,.45);color:#38F27A;font-size:12px;font-weight:800">● CANLI BULUT SENKRON</span>
    </div>

    <div class="grid2" style="margin-top:14px">
      <div class="metric"><span class="note">Kayıtlı Üye Restoran / Şube</span><b>${stores.length}</b></div>
      <div class="metric"><span class="note">Aktif Sipariş / Yoldaki Araç</span><b style="color:#3AF1D7">${validOrd.length} Sipariş (${approachingCars} Yolda)</b></div>
      <div class="metric"><span class="note">Türkiye Geneli Brüt Ciro (GMV)</span><b>₺${totalGmv}</b></div>
      <div class="metric"><span class="note">👑 Konumum Yemek Net Komisyon (%${Math.round(COMMISSION * 100)})</span><b style="color:#38F27A;font-size:22px">₺${totalCommission}</b></div>
      <div class="metric"><span class="note">Restoranlara Ödenecek Net Hakediş (%${Math.round((1 - COMMISSION) * 100)})</span><b style="color:#FFD129">₺${totalNetToRestaurants}</b></div>
      <div class="metric"><span class="note">Kurumsal E-Posta &amp; Destek Kutusu</span><b style="font-size:14px;color:#3AF1D7">info@konumumyemek.com (${tickets.length} Talep)</b></div>
    </div>

    <h3 style="margin-top:22px;color:var(--neon)">🧾 Otomatik Komisyon (%${Math.round(COMMISSION * 100)}) &amp; e-Fatura Mutabakat Tablosu</h3>
    <p class="note">iyzico Pazaryeri (Split Payment) ve otomatik e-Fatura kesimi için şube bazlı anlık komisyon dağılımı.</p>
    <div style="margin-top:10px;display:grid;gap:8px">
      ${Object.values(byStore).map((row) => {
        const s = row.store;
        const invNo = `KYF-${dayCode}-${String(s.bayiKodu || s.id).toUpperCase()}`;
        const hasBilling = Boolean(s.taxNumber && s.iban && s.iban.length >= 10);
        return `<div class="list-item" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">
          <div>
            <b>${esc(s.branchTitle || s.id)}</b> <span class="note">(${esc(s.bayiKodu || s.id)})</span><br/>
            <span class="note" style="font-size:11px">Fatura No: <b>${esc(invNo)}</b> · VKN: ${esc(s.taxNumber || "Henüz Girilmedi")} · IBAN: ${esc(s.iban || "Henüz Girilmedi")}</span>
          </div>
          <div style="text-align:right">
            <span class="note">${row.count} Sipariş · Brüt ₺${row.gmv}</span><br/>
            <b style="color:#38F27A">Komisyon (%${Math.round(COMMISSION * 100)}): ₺${row.fee}</b> · <span style="color:#FFD129;font-weight:700">Restoran Net: ₺${row.net}</span>
            <span style="margin-left:8px;padding:3px 8px;border-radius:6px;font-size:10px;font-weight:800;background:${hasBilling ? "rgba(56,242,122,.15)" : "rgba(255,209,41,.15)"};color:${hasBilling ? "#38F27A" : "#FFD129"}">${hasBilling ? "✓ Fatura/IBAN Hazır" : "⏳ VKN/IBAN Bekleniyor"}</span>
          </div>
        </div>`;
      }).join("")}
    </div>

    <h3 style="margin-top:22px;color:var(--neon)">🏪 Kayıtlı Üye İşyerleri &amp; Doğrudan Yönetim (${stores.length} Mağaza)</h3>
    <p class="note">Instagram veya web üzerinden üye olan tüm restoranların iletişim, VKN, IBAN bilgileri ve tek tıkla mağaza görünümüne geçiş.</p>
    <div style="margin-top:10px;display:grid;gap:8px">
      ${stores.map((s) => {
        const st = storeOpenState(s.id);
        const complete = Boolean(s.taxNumber && s.iban && s.iban.length >= 10);
        return `<div class="list-item" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px">
          <div style="line-height:1.5">
            <b>${esc(s.branchTitle)}</b> <span style="color:var(--neon);font-family:ui-monospace,Menlo,monospace;font-size:12px">[${esc(s.bayiKodu || s.id)}]</span>
            ${st.effectiveOpen ? `<span style="color:#38F27A;font-size:11px;font-weight:800">● AÇIK</span>` : `<span style="color:#FF4272;font-size:11px;font-weight:800">● KAPALI</span>`}
            ${complete ? `<span style="color:#3AF1D7;font-size:11px;margin-left:6px">✓ Resmi Evrak Tamam</span>` : `<span style="color:#FFD129;font-size:11px;margin-left:6px">⚡ Hızlı Üye (VKN/IBAN Sonradan Girilecek)</span>`}<br/>
            <span class="note" style="font-size:11px">📧 ${esc(s.email || "—")} · 📞 ${esc(s.phone || "Belirtilmedi")} · 🏢 ${esc(s.officialTitle || "—")}</span><br/>
            <span class="note" style="font-size:11px">🏛️ Vergi Dairesi/VKN: ${esc(s.taxOffice || "—")} / ${esc(s.taxNumber || "—")} · 💳 IBAN: <span style="font-family:ui-monospace,Menlo,monospace">${esc(s.iban || "—")}</span></span>
          </div>
          <div>
            <button type="button" class="mini" data-hq-switch="${esc(s.id)}" style="border-color:var(--neon);color:var(--neon);font-weight:800">Mağazayı Denetle</button>
          </div>
        </div>`;
      }).join("")}
    </div>

    <h3 style="margin-top:22px;color:var(--neon)">💬 Web Sitesinden Gelen Destek &amp; İletişim Talepleri (info@konumumyemek.com)</h3>
    <div style="margin-top:10px;display:grid;gap:8px">
      ${tickets.length ? tickets.map((t, idx) => `
        <div class="list-item" style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;flex-wrap:wrap">
          <div>
            <b>${esc(t.name)}</b> <span class="note">(${esc(t.contact)})</span> · <span class="note" style="font-size:11px">${esc(new Date(t.createdAt || Date.now()).toLocaleString("tr-TR"))}</span>
            <div style="margin-top:4px;font-size:13px;color:var(--ink)">${esc(t.message)}</div>
          </div>
          <button type="button" class="mini" data-del-ticket="${idx}" style="color:#FF4272;border-color:rgba(255,66,114,.5)">Arşivle / Sil</button>
        </div>
      `).join("") : `<p class="note">Henüz web formundan gönderilmiş bir destek talebi yok. Restoranların veya müşterilerin <b>"💬 Bize Ulaşın / Destek Talebi"</b> butonundan yazdığı tüm mesajlar anında buraya düşer.</p>`}
    </div>
  </div>`;

  [...pane.querySelectorAll("[data-hq-switch]")].forEach((btn) => {
    btn.onclick = () => {
      switchBranch(btn.dataset.hqSwitch);
      showTab("home");
    };
  });
  [...pane.querySelectorAll("[data-del-ticket]")].forEach((btn) => {
    btn.onclick = async () => {
      const i = Number(btn.dataset.delTicket);
      if (Array.isArray(runtime.supportTickets)) {
        runtime.supportTickets.splice(i, 1);
        await persist();
        renderHq();
      }
    };
  });
}

function renderLegal() {
  const p = Object.assign({}, session || {}, (session && runtime.profiles?.[session.id]) || {});
  $("legalPane").innerHTML = `<div class="card legal">
    <h2>Restoran Üye İşyeri Sözleşmesi, Hakediş/IBAN ve KVKK Yasal Standartları</h2>
    <p class="note">konumumyemek.com tersine araç takip ve araç camından teslim (Drive-Thru / Curbside) platformu resmi hukuki metinleri.</p>

    <div style="margin:12px 0 16px 0;padding:12px 14px;border-radius:12px;background:rgba(58,241,215,.06);border:1px solid rgba(58,241,215,.3);font-size:12px;line-height:1.6">
      <b style="color:var(--neon)">Aktif Üye İşyeri Kayıt Özeti:</b><br/>
      • <b>Ticari Unvan / Şube:</b> ${esc(p.officialTitle || p.branchTitle || "—")} (${esc(p.bayiKodu || "—")})<br/>
      • <b>Vergi Dairesi &amp; VKN/TCKN:</b> ${esc(p.taxOffice || "Belirtilmedi")} / ${esc(p.taxNumber || "Belirtilmedi")}<br/>
      • <b>Kayıtlı Hakediş IBAN:</b> <span style="font-family:ui-monospace,Menlo,monospace">${esc(p.iban || "Belirtilmedi (Restoran Profili sekmesinden güncelleyiniz)")}</span>
    </div>

    <h3>1. 6698 Sayılı KVKK Aydınlatma Metni ve Veri İşleyen / Veri Sorumlusu Protokolü</h3>
    <p>Müşterinin mobil uygulamadan verdiği siparişlerde <b>araç plakası</b>, <b>ad-soyad/iletişim bilgisi</b> ve <b>canlı GPS yaklaşım mesafesi (metre / tahmini varış süresi)</b>, 6698 sayılı Kişisel Verilerin Korunması Kanunu m.5/2-c ("bir sözleşmenin kurulması veya ifasıyla doğrudan doğruya ilgili olması") hukuki sebebine dayanarak yalnızca siparişin zamanında hazırlanması ve araç camından doğru araca teslim edilmesi amacıyla mutfak ekranında (KDS) gösterilir. Sipariş <b>"Camdan Teslim"</b> veya <b>"İptal"</b> statüsüne geçtiği anda canlı konum akışı otomatik olarak kesilir. Üye işyeri, plaka ve müşteri verilerini üçüncü kişilerle paylaşamaz veya pazarlama amacıyla kullanamaz.</p>

    <h3>2. 6563 Sayılı ETK Kapsamında Aracı Hizmet Sağlayıcı &amp; Üye İşyeri Sözleşmesi</h3>
    <p><b>konumumyemek.com</b>, 6563 sayılı Elektronik Ticaretin Düzenlenmesi Hakkında Kanun kapsamında "Aracı Hizmet Sağlayıcı" sıfatıyla hareket eder. Üye İşyeri (Restoran), platformda satışa sunduğu gıda ve içecek ürünlerinin fiyat, içerik, gramaj bilgilerinin doğruluğundan, e-Arşiv / ÖKC fiş düzenleme yükümlülüğünden ve 213 sayılı Vergi Usul Kanunu uyarınca vergisel sorumluluklardan bizzat sorumludur.</p>

    <h3>3. 6493 Sayılı Kanun, Komisyon Oranı (%${Math.round(COMMISSION * 100)}) ve TR IBAN Hakediş Mutabakatı</h3>
    <p>Mobil uygulama üzerinden Kredi / Banka Kartları (Visa, Mastercard, Troy) ve Yemek Kartları (Sodexo/Pluxee, Multinet, Setcard, Metropol Card, Ticket Edenred) ile tahsil edilen sipariş tutarlarından <b>%${Math.round(COMMISSION * 100)} platform hizmet komisyonu (KDV dahil)</b> düşüldükten sonra kalan <b>Net Restoran Hakedişi</b>, Üye İşyerinin bildirdiği 26 haneli <b>TR IBAN</b> hesabına aktarılır. MASAK ve 6493 sayılı Ödeme Hizmetleri Kanunu gereğince IBAN alıcı ünvanı ile kayıtlı Vergi Kimlik Numarası (VKN/TCKN) sahibi birebir aynı tüzel veya gerçek kişi olmak zorundadır.</p>

    <h3>4. 6502 Sayılı TKHK &amp; Mesafeli Sözleşmeler Yönetmeliği m.15/1-c (İptal ve Cayma İstisnası)</h3>
    <p>Mesafeli Sözleşmeler Yönetmeliği m.15/1-c uyarınca <i>"çabuk bozulabilen veya son kullanma tarihi geçebilecek malların teslimine ilişkin sözleşmelerde"</i> hazırlık başladıktan sonra cayma hakkı kullanılamaz. Müşteri yalnızca sipariş <b>"İletildi"</b> aşamasındayken uygulama üzerinden ücretsiz iptal yapabilir. Restoran siparişi KDS ekranında <b>"Mutfağa Al"</b> olarak onayladıktan sonra gıda üretimi başladığından müşteri kaynaklı iptal yapılamaz.</p>

    <h3>5. 5996 Sayılı Gıda Güvenliği Kanunu, Alerjen ve Kalori Bildirimi</h3>
    <p>Üye İşyeri, Türk Gıda Kodeksi Etiketleme ve Tüketicileri Bilgilendirme Yönetmeliği uyarınca menüsündeki ürünlerin alerjen bilgilerini (Glüten, Süt/Laktoz, Yumurta, Fıstık, Susam, Soya, Deniz Ürünü vb.) ve kalori değerlerini "Menü &amp; Stok (86)" sekmesinde doğru şekilde işaretlemekle ve tükenen ürünleri ("86 · Tükendi") anlık olarak kapatmakla yükümlüdür.</p>

    <h3>6. KVKK m.7 &amp; m.11 Kapsamında Mağaza Kapatma ve Veri İmha Prosedürü</h3>
    <p>Üye İşyeri dilediği zaman <b>Restoran Profili &gt; Mağazamı ve İşletme Hesabımı Kalıcı Olarak Sil</b> adımı üzerinden üyeliğini tek tıkla sonlandırabilir. Silme işlemi onaylandığında mağaza profili, menü, kampanya ve canlı takip kayıtları aktif bulut veritabanından derhal silinir ve mobil müşteri uygulamasından kaldırılır.</p>
  </div>`;
}

function printSlip(id) {
  const order = (runtime.orders || []).find((o) => o.id === id);
  if (!order) return;
  const slip = window.open("", "adisyon", "width=380,height=640");
  if (!slip) return;
  slip.document.write(`<!doctype html><title>Adisyon · ${esc(order.plate)}</title>
    <body style="font-family:ui-monospace,Menlo,monospace;padding:16px">
    <h2>konumumyemek.com</h2>
    <p><b>${esc((session && session.branchTitle) || "")}</b></p>
    <hr/>
    <p><b>ARAÇ PLAKA: ${esc(order.plate || "")}</b></p>
    <p>Müşteri: ${esc(order.driverName || order.customer || "")}</p>
    <p>Kalemler: ${esc(order.items || "")}</p>
    <p>Ödeme: ${esc(order.payment || "")} · <b>₺${Number(order.total || 0)}</b></p>
    <hr/>
    <p>Teslimat: Araç camından teslim (0 m)</p>
    <script>window.onload=()=>window.print()<\/script>
    </body>`);
  slip.document.close();
}

async function persist(replaceOrders = false) {
  localStorage.setItem("konumum.web.runtime", JSON.stringify(runtime));
  const nowIso = new Date().toISOString();
  const accountRows = [];
  Object.entries(runtime.profiles || {}).forEach(([id, prof]) => {
    if (prof && prof.email && prof.password) {
      const payload = { ...prof, id };
      accountRows.push({
        key: "account:" + String(prof.email).trim().toLowerCase(),
        payload,
        updated_at: nowIso
      });
      if (prof.bayiKodu) {
        accountRows.push({
          key: "account:" + String(prof.bayiKodu).trim().toLowerCase(),
          payload,
          updated_at: nowIso
        });
      }
    }
  });
  const rows = [
    { key: "menus", payload: runtime.menus || {}, updated_at: nowIso },
    { key: "menuExtras", payload: runtime.menuExtras || {}, updated_at: nowIso },
    { key: "profiles", payload: runtime.profiles || {}, updated_at: nowIso },
    { key: "campaigns", payload: runtime.campaigns || [], updated_at: nowIso },
    { key: "supportTickets", payload: runtime.supportTickets || [], updated_at: nowIso },
    ...accountRows
  ];
  const orderStateRows = rows.map((r) => ({
    id: "__state_" + r.key,
    restaurant_id: "__system__",
    plate: "__SYS__",
    items: JSON.stringify(r.payload),
    order_status: "iptal",
    source: "system_state",
    updated_at: nowIso
  }));
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/orders?on_conflict=id`, {
      method: "POST",
      headers: supabaseHeaders("resolution=merge-duplicates,return=minimal"),
      body: JSON.stringify(orderStateRows)
    });
  } catch { /* fallback */ }
  if (sbClient) {
    try {
      await sbClient.from("orders").upsert(orderStateRows, { onConflict: "id" });
    } catch { /* fallback */ }
  }
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/restaurant_state?on_conflict=key`, {
      method: "POST",
      headers: supabaseHeaders("resolution=merge-duplicates,return=minimal"),
      body: JSON.stringify(rows)
    });
  } catch { /* fallback */ }
  if (location.hostname === "localhost" || location.hostname === "127.0.0.1") {
    try {
      await fetch("data/runtime.sync.json", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          menuExtras: runtime.menuExtras,
          menus: runtime.menus || {},
          profiles: runtime.profiles,
          campaigns: runtime.campaigns,
          orders: runtime.orders,
          replaceOrders
        })
      });
    } catch { /* static */ }
  }
}

boot();
