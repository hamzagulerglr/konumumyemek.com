#!/usr/bin/env python3
"""
konumumyemek.com · Production Realtime Cloud Bus (Supabase PostgreSQL + Railway WSS/HTTP)
- runtime.json dosya bağımlılığı tamamen kaldırılmıştır.
- Veritabanı katmanı: supabase-py (`orders`, `live_tracking`, `restaurant_state`) + bellek içi hızlı önbellek.
- Haversine formülü ile metre cinsinden hassas mesafe hesabı ve < 500 m için `"trigger_alarm": True` bayrağı.
"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import base64
import hashlib
import json
import math
import os
import struct
import threading
import time
from datetime import datetime, timezone

try:
    from supabase import create_client, Client as SupabaseClient  # type: ignore
except ImportError:
    create_client = None
    SupabaseClient = None

ROOT = os.path.dirname(os.path.abspath(__file__))
SEED = os.path.join(ROOT, "data", "seed.json")
PORT = int(os.environ.get("PORT") or os.environ.get("KONUMUM_WEB_PORT") or "8765")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://hetcihydnkgbuglsuzcs.supabase.co").strip()
SUPABASE_KEY = (
    os.environ.get("SUPABASE_ANON_KEY", "sb_publishable_Xh8V52jmvs1JFpKX7v8SuA_SFk1DA0Z").strip()
    or os.environ.get("SUPABASE_KEY", "").strip()
    or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
)

SUPABASE = None
if create_client and SUPABASE_URL and SUPABASE_KEY:
    try:
        SUPABASE = create_client(SUPABASE_URL, SUPABASE_KEY)
        print(f"[cloud] Supabase baglantisi aktif: {SUPABASE_URL}", flush=True)
    except Exception as exc:
        print(f"[cloud] Supabase baslatilamadi, bellek-ici (in-memory) modda devam ediliyor: {exc}", flush=True)

LOCK = threading.Lock()
HUB_LOCK = threading.Lock()
HUB = []
STARTED = datetime.now(timezone.utc).isoformat()
LOGIN_HITS = {}
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
START_M = 1400
ALARM_THRESHOLD_M = 500
APPROACH_SPEED_MPS = 10.0

# In-memory state synchronized with Supabase PostgreSQL tables
STATE = {
    "menuExtras": {},
    "menus": {},
    "profiles": {},
    "campaigns": [],
    "orders": [],
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: str, fallback):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return fallback


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> int:
    """İki GPS koordinatı arasındaki mesafeyi Haversine formülü ile metre cinsinden hesaplar."""
    earth_radius_m = 6_371_000.0
    phi1 = math.radians(float(lat1))
    phi2 = math.radians(float(lat2))
    d_phi = math.radians(float(lat2) - float(lat1))
    d_lambda = math.radians(float(lon2) - float(lon1))

    a = (
        math.sin(d_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * (math.sin(d_lambda / 2.0) ** 2)
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    return max(0, int(round(earth_radius_m * c)))


def eta_seconds_for(distance_meters: int) -> int:
    return max(0, int(round(max(0, int(distance_meters)) / APPROACH_SPEED_MPS)))


def restaurant_pin(restaurant_id: str):
    seed = load_json(SEED, {})
    for row in seed.get("restaurants") or []:
        if row.get("id") == restaurant_id:
            return float(row.get("mapLatitude") or 41.2867), float(row.get("mapLongitude") or 36.33)
    return 41.2867, 36.33


def interpolate_coords(restaurant_id: str, meters: int):
    lat, lng = restaurant_pin(restaurant_id)
    progress = 1.0 - (max(0, min(START_M, int(meters or 0))) / float(START_M))
    # ~1400 metre başlangıç ofseti (~0.0089 derece enlem/boylam)
    start_lat, start_lng = lat - 0.0089, lng - 0.0089
    return round(start_lat + (lat - start_lat) * progress, 6), round(start_lng + (lng - start_lng) * progress, 6)


def normalize_order(order: dict) -> dict:
    row = dict(order)
    row["id"] = str(row.get("id") or ("o-" + str(int(time.time() * 1000))))
    row["restaurantId"] = row.get("restaurantId") or row.get("restaurant_id") or "mcd-samsun"
    row["driverName"] = row.get("driverName") or row.get("driver_name") or row.get("customer") or ""
    row["customer"] = row.get("customer") or row.get("customer_name") or row.get("driverName") or ""
    row["plate"] = row.get("plate") or ""
    row["items"] = row.get("items") or ""
    row["payment"] = row.get("payment") or row.get("payment_method") or "Metropol Card"

    rest_lat, rest_lng = restaurant_pin(row["restaurantId"])
    has_coords = row.get("latitude") is not None and row.get("longitude") is not None

    if row.get("meters") is not None or row.get("distance_meters") is not None:
        raw_m = row.get("meters") if row.get("meters") is not None else row.get("distance_meters")
        meters = max(0, int(raw_m))
        if not has_coords:
            lat, lng = interpolate_coords(row["restaurantId"], meters)
            row["latitude"] = lat
            row["longitude"] = lng
        else:
            row["latitude"] = float(row["latitude"])
            row["longitude"] = float(row["longitude"])
    elif has_coords:
        row["latitude"] = float(row["latitude"])
        row["longitude"] = float(row["longitude"])
        meters = haversine_meters(row["latitude"], row["longitude"], rest_lat, rest_lng)
    else:
        meters = START_M
        lat, lng = interpolate_coords(row["restaurantId"], meters)
        row["latitude"] = lat
        row["longitude"] = lng

    row["meters"] = meters
    row["distance_meters"] = meters
    row["eta_seconds"] = int(row.get("eta_seconds") if row.get("eta_seconds") is not None else eta_seconds_for(meters))

    status = row.get("status") or row.get("order_status")
    if not status:
        status = "kapıda" if meters == 0 else "iletildi"
    row["status"] = status

    active = status not in ("teslim", "iptal")
    row["trigger_alarm"] = bool(active and meters < ALARM_THRESHOLD_M)
    row["total"] = int(row.get("total") if row.get("total") is not None else (row.get("total_amount") or 0))
    row["source"] = row.get("source") or "ios"
    if row.get("prepMinutes") not in (None, "") or row.get("prep_minutes") not in (None, ""):
        row["prepMinutes"] = int(row.get("prepMinutes") or row.get("prep_minutes") or 0)
    if row.get("cancelReason") or row.get("cancel_reason"):
        row["cancelReason"] = str(row.get("cancelReason") or row.get("cancel_reason"))
    row["lane"] = row.get("lane") or ""
    row["stall"] = int(row.get("stall") or 0)
    row["speaker"] = int(row.get("speaker") or 0)
    row["speakerMatched"] = bool(row.get("speakerMatched") or row.get("speaker_matched"))
    row["atDoor"] = bool(row.get("atDoor") or row.get("at_door") or meters == 0)
    row["seenCar"] = bool(row.get("seenCar") or row.get("seen_car"))
    row["updatedAt"] = now_iso()
    return row


def supabase_Bootstrap():
    """Sunucu açılışında Supabase tablolarındaki son durumu belleğe yükler."""
    if not SUPABASE:
        return
    try:
        state_res = SUPABASE.table("restaurant_state").select("key,payload").execute()
        for item in state_res.data or []:
            k = item.get("key")
            val = item.get("payload")
            if k in ("menus", "menuExtras", "profiles", "campaigns") and val is not None:
                STATE[k] = val

        orders_res = SUPABASE.table("orders").select("*").order("updated_at", desc=True).limit(200).execute()
        track_res = SUPABASE.table("live_tracking").select("*").execute()
        track_by_id = {row["order_id"]: row for row in (track_res.data or []) if row.get("order_id")}

        loaded_orders = []
        for o in orders_res.data or []:
            oid = o.get("id")
            tr = track_by_id.get(oid, {})
            merged = {
                "id": oid,
                "restaurantId": o.get("restaurant_id"),
                "driverName": o.get("driver_name"),
                "customer": o.get("customer_name"),
                "plate": o.get("plate"),
                "items": o.get("items"),
                "payment": o.get("payment_method"),
                "total": o.get("total_amount"),
                "status": o.get("order_status"),
                "cancelReason": o.get("cancel_reason") or "",
                "prepMinutes": o.get("prep_minutes") or 0,
                "lane": o.get("lane") or "",
                "stall": o.get("stall") or 0,
                "speaker": o.get("speaker") or 0,
                "speakerMatched": bool(o.get("speaker_matched")),
                "atDoor": bool(o.get("at_door")),
                "seenCar": bool(o.get("seen_car")),
                "source": o.get("source") or "ios",
                "latitude": tr.get("latitude"),
                "longitude": tr.get("longitude"),
                "meters": tr.get("distance_meters", START_M),
                "eta_seconds": tr.get("eta_seconds", eta_seconds_for(tr.get("distance_meters", START_M))),
            }
            loaded_orders.append(normalize_order(merged))
        with LOCK:
            STATE["orders"] = loaded_orders
        print(f"[cloud] Supabase'den {len(loaded_orders)} siparis yuklendi.", flush=True)
    except Exception as exc:
        print(f"[cloud] Supabase baslangic senkronizasyonu hatasi: {exc}", flush=True)


def supabase_sync_order(row: dict):
    """Siparişi ve anlık konum bilgisini Supabase `orders` ve `live_tracking` tablolarına yazar."""
    if not SUPABASE:
        return
    try:
        order_doc = {
            "id": row["id"],
            "restaurant_id": row["restaurantId"],
            "driver_name": row.get("driverName") or "",
            "customer_name": row.get("customer") or "",
            "plate": row.get("plate") or "",
            "items": row.get("items") or "",
            "payment_method": row.get("payment") or "Metropol Card",
            "total_amount": int(row.get("total") or 0),
            "order_status": row.get("status") or "iletildi",
            "cancel_reason": row.get("cancelReason") or "",
            "prep_minutes": int(row.get("prepMinutes") or 0),
            "lane": row.get("lane") or "",
            "stall": int(row.get("stall") or 0),
            "speaker": int(row.get("speaker") or 0),
            "speaker_matched": bool(row.get("speakerMatched")),
            "at_door": bool(row.get("atDoor")),
            "seen_car": bool(row.get("seenCar")),
            "source": row.get("source") or "ios",
            "updated_at": row.get("updatedAt") or now_iso(),
        }
        tracking_doc = {
            "order_id": row["id"],
            "restaurant_id": row["restaurantId"],
            "plate": row.get("plate") or "",
            "latitude": float(row.get("latitude") or 41.2867),
            "longitude": float(row.get("longitude") or 36.3300),
            "distance_meters": int(row.get("meters") or 0),
            "eta_seconds": int(row.get("eta_seconds") or eta_seconds_for(int(row.get("meters") or 0))),
            "order_status": row.get("status") or "iletildi",
            "trigger_alarm": bool(row.get("trigger_alarm")),
            "at_door": bool(row.get("atDoor")),
            "updated_at": row.get("updatedAt") or now_iso(),
        }
        SUPABASE.table("orders").upsert(order_doc, on_conflict="id").execute()
        SUPABASE.table("live_tracking").upsert(tracking_doc, on_conflict="order_id").execute()
    except Exception as exc:
        print(f"[cloud] Supabase order/live_tracking yazma hatasi: {exc}", flush=True)


def supabase_sync_state_key(key: str, value):
    if not SUPABASE:
        return
    try:
        SUPABASE.table("restaurant_state").upsert(
            {"key": key, "payload": value, "updated_at": now_iso()},
            on_conflict="key",
        ).execute()
    except Exception as exc:
        print(f"[cloud] Supabase restaurant_state ({key}) yazma hatasi: {exc}", flush=True)


def supabase_delete_orders(order_ids: list):
    if not SUPABASE or not order_ids:
        return
    try:
        SUPABASE.table("orders").delete().in_("id", order_ids).execute()
    except Exception as exc:
        print(f"[cloud] Supabase siparis silme hatasi: {exc}", flush=True)


def snapshot_state() -> dict:
    return {
        "menuExtras": dict(STATE["menuExtras"]),
        "menus": dict(STATE["menus"]),
        "profiles": dict(STATE["profiles"]),
        "campaigns": list(STATE["campaigns"]),
        "orders": list(STATE["orders"]),
    }


def pick_speaker(used, requested=0):
    want = int(requested or 0)
    if want in (1, 2) and want not in used:
        return want
    return 1 if 1 not in used else 2


def apply_drive(order_id, action, speaker_n=0):
    row = None
    for existing in STATE["orders"]:
        if existing.get("id") == order_id:
            row = existing
            break
    if not row:
        return None
    restaurant = row.get("restaurantId")
    used = {
        int(o.get("speaker") or 0)
        for o in STATE["orders"]
        if o.get("restaurantId") == restaurant
        and o.get("id") != order_id
        and o.get("status") not in ("teslim", "iptal")
        and int(o.get("speaker") or 0)
    }
    if action == "speaker":
        speaker = pick_speaker(used, speaker_n)
        row["speaker"] = speaker
        row["lane"] = "A" if speaker == 1 else "B"
        row["stall"] = 0
        row["speakerMatched"] = False
        row["atDoor"] = False
        if row.get("status") in ("hazir", "iletildi", "kabul"):
            row["status"] = "yolda"
        row["meters"] = min(int(row.get("meters") or 35), 35)
    elif action == "match":
        speaker = int(row.get("speaker") or 0) or pick_speaker(used, speaker_n)
        row["speaker"] = speaker
        row["lane"] = row.get("lane") or ("A" if speaker == 1 else "B")
        row["stall"] = speaker
        row["speakerMatched"] = True
        if row.get("status") in ("iletildi", "kabul", "hazir"):
            row["status"] = "yolda"
        row["meters"] = min(int(row.get("meters") or 18), 18)
    elif action == "door":
        if not row.get("speaker"):
            speaker = pick_speaker(used, speaker_n)
            row["speaker"] = speaker
            row["lane"] = "A" if speaker == 1 else "B"
        row["stall"] = int(row.get("stall") or row.get("speaker") or 1)
        row["atDoor"] = True
        row["meters"] = 0
        row["status"] = "kapıda"
    elif action == "seen":
        row["seenCar"] = True
        row["atDoor"] = True
    row.update(normalize_order(row))
    return row


def rate_ok(ip, limit=25, window=60):
    now = time.time()
    bucket = [stamp for stamp in LOGIN_HITS.get(ip, []) if now - stamp < window]
    if len(bucket) >= limit:
        LOGIN_HITS[ip] = bucket
        return False
    bucket.append(now)
    LOGIN_HITS[ip] = bucket
    return True


def catalog():
    seed = load_json(SEED, {"restaurants": []})
    with LOCK:
        runtime = snapshot_state()
    extras = runtime.get("menuExtras") or {}
    menus = runtime.get("menus") or {}
    restaurants = []
    for row in seed.get("restaurants") or []:
        item = dict(row)
        rid = row.get("id")
        profile = (runtime.get("profiles") or {}).get(rid) or {}
        for key in ("cuisine", "hours", "logoMark", "logoBg", "logoFg", "branchTitle", "officialTitle", "address", "phone"):
            if profile.get(key):
                item[key] = profile[key]
        item["open"] = profile.get("open", True) is not False
        item["busy"] = profile.get("busy") or "mid"
        if menus.get(rid):
            item["menu"] = list(menus[rid])
        else:
            item["menu"] = list(row.get("menu") or []) + list(extras.get(rid) or [])
        restaurants.append(item)
    return {
        "product": seed.get("product", "konumumyemek.com"),
        "demo": seed.get("demo", {}),
        "restaurants": restaurants,
        "campaigns": runtime.get("campaigns") or [],
        "orders": runtime.get("orders") or [],
        "menus": menus,
        "menuExtras": extras,
        "profiles": runtime.get("profiles") or {},
    }


def ws_accept(key):
    digest = hashlib.sha1((key + WS_GUID).encode("utf-8")).digest()
    return base64.b64encode(digest).decode("ascii")


def encode_ws(payload, opcode=1):
    header = bytearray()
    header.append(0x80 | opcode)
    length = len(payload)
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", length))
    return bytes(header) + payload


def broadcast(event):
    blob = json.dumps(event, ensure_ascii=False).encode("utf-8")
    frame = encode_ws(blob)
    dead = []
    with HUB_LOCK:
        clients = list(HUB)
    for client in clients:
        try:
            client.send_ws(frame)
        except Exception:
            dead.append(client)
    if dead:
        with HUB_LOCK:
            for client in dead:
                if client in HUB:
                    HUB.remove(client)


def upsert_order(order, sync_db=True):
    incoming = {key: value for key, value in dict(order).items() if value not in (None, "")}
    with LOCK:
        found = False
        for index, existing in enumerate(STATE["orders"]):
            if existing.get("id") == incoming.get("id"):
                merged = dict(existing)
                merged.update(incoming)
                # Eğer yeni koordinat geldiyse fakat açıkça meters verilmediyse Haversine ile hesapla
                if (
                    "latitude" in incoming
                    and "longitude" in incoming
                    and "meters" not in incoming
                    and "distance_meters" not in incoming
                ):
                    rlat, rlng = restaurant_pin(merged.get("restaurantId") or "mcd-samsun")
                    merged["meters"] = haversine_meters(
                        float(incoming["latitude"]),
                        float(incoming["longitude"]),
                        rlat,
                        rlng,
                    )
                STATE["orders"][index] = normalize_order(merged)
                row = dict(STATE["orders"][index])
                found = True
                break
        if not found:
            row = normalize_order(incoming)
            STATE["orders"].insert(0, row)
            row = dict(row)

    if sync_db:
        threading.Thread(target=supabase_sync_order, args=(row,), daemon=True).start()

    trigger_alarm = bool(row.get("trigger_alarm"))
    ws_event = {
        "type": "order.upsert",
        "order": row,
        "trigger_alarm": trigger_alarm,
        "distance_meters": int(row.get("meters") or 0),
        "eta_seconds": int(row.get("eta_seconds") or 0),
    }
    broadcast(ws_event)
    if int(row.get("meters") or 0) == 0:
        broadcast({"type": "order.door", "order": row, "trigger_alarm": True})
    return row


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        self.ws_lock = threading.Lock()
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def send_ws(self, frame):
        with self.ws_lock:
            self.wfile.write(frame)
            self.wfile.flush()

    def read_ws(self):
        header = self.rfile.read(2)
        if not header or len(header) < 2:
            return None, None
        opcode = header[0] & 0x0F
        masked = header[1] & 0x80
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self.rfile.read(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self.rfile.read(8))[0]
        mask = self.rfile.read(4) if masked else b""
        raw = self.rfile.read(length) if length else b""
        if masked:
            raw = bytes(b ^ mask[i % 4] for i, b in enumerate(raw))
        return opcode, raw

    def handle_ws_message(self, payload: bytes):
        """Müşteriden WebSocket üzerinden doğrudan gelen konum / sipariş paketlerini işler ve Supabase'e yazar."""
        try:
            msg = json.loads(payload.decode("utf-8"))
        except Exception:
            return
        if not isinstance(msg, dict):
            return
        msg_type = msg.get("type") or msg.get("action") or "location"
        if msg_type in ("location", "location.update", "order.location") and msg.get("id"):
            order_id = str(msg["id"])
            with LOCK:
                existing = next((o for o in STATE["orders"] if o.get("id") == order_id), None)
                rest_id = (existing or {}).get("restaurantId") or msg.get("restaurantId") or "mcd-samsun"
                existing_status = (existing or {}).get("status")

            patch = {"id": order_id, "restaurantId": rest_id, "source": msg.get("source") or "ios"}
            if msg.get("latitude") is not None and msg.get("longitude") is not None:
                lat = float(msg["latitude"])
                lng = float(msg["longitude"])
                patch["latitude"] = lat
                patch["longitude"] = lng
                if msg.get("meters") is not None or msg.get("distance_meters") is not None:
                    patch["meters"] = int(msg.get("meters") if msg.get("meters") is not None else msg.get("distance_meters"))
                else:
                    rlat, rlng = restaurant_pin(rest_id)
                    patch["meters"] = haversine_meters(lat, lng, rlat, rlng)
            elif msg.get("meters") is not None or msg.get("distance_meters") is not None:
                patch["meters"] = int(msg.get("meters") if msg.get("meters") is not None else msg.get("distance_meters"))

            if existing_status not in ("iletildi", "kabul", "hazir", "teslim", "iptal") and patch.get("meters") == 0:
                patch["status"] = "kapıda"
            upsert_order(patch)
        elif msg_type in ("order.create", "order") and msg.get("restaurantId"):
            upsert_order(msg)

    def handshake_ws(self):
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_error(400)
            return
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", ws_accept(key))
        self.end_headers()
        with HUB_LOCK:
            HUB.append(self)
        try:
            with LOCK:
                snap = snapshot_state()
            self.send_ws(encode_ws(json.dumps({"type": "snapshot", "state": snap}, ensure_ascii=False).encode("utf-8")))
            while True:
                opcode, payload = self.read_ws()
                if opcode is None or opcode == 8:
                    break
                if opcode == 9:
                    self.send_ws(encode_ws(payload or b"", opcode=10))
                elif opcode == 1 and payload:
                    self.handle_ws_message(payload)
        finally:
            with HUB_LOCK:
                if self in HUB:
                    HUB.remove(self)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/ws":
            self.handshake_ws()
            return
        if path == "/api/health":
            self.send_json({
                "ok": True,
                "service": "konumum-cloud",
                "database": "supabase-postgresql" if SUPABASE else "in-memory-fallback",
                "supabaseConnected": bool(SUPABASE),
                "realtime": "websocket",
                "started": STARTED,
                "clients": len(HUB),
            })
            return
        if path in ("/api/state", "/api/menus", "/api/live"):
            with LOCK:
                snap = snapshot_state()
            self.send_json(snap)
            return
        if path == "/api/catalog":
            self.send_json(catalog())
            return
        if path == "/api/orders":
            with LOCK:
                orders = list(STATE["orders"])
            self.send_json({"orders": orders})
            return
        if path == "/api/cloud-config":
            self.send_json(load_json(os.path.join(ROOT, "cloud.config.json"), {}))
            return
        if path in ("/", "/restoran-panel"):
            self.path = "/panel.html"
        super().do_GET()

    def do_PUT(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/menus":
            payload = self.read_json()
            restaurant_id = payload.get("restaurantId")
            items = payload.get("items")
            if not restaurant_id or not isinstance(items, list):
                self.send_error(400)
                return
            with LOCK:
                STATE["menus"][restaurant_id] = items
                STATE["menuExtras"][restaurant_id] = [
                    row for row in items if str(row.get("id", "")).startswith("web-")
                ]
                menus = dict(STATE["menus"])
                extras = dict(STATE["menuExtras"])
            threading.Thread(target=supabase_sync_state_key, args=("menus", menus), daemon=True).start()
            threading.Thread(target=supabase_sync_state_key, args=("menuExtras", extras), daemon=True).start()
            broadcast({"type": "menus", "menus": menus})
            self.send_json({"ok": True})
            return
        if path != "/api/state":
            self.send_error(404)
            return
        payload = self.read_json()
        if not isinstance(payload, dict):
            self.send_error(400)
            return
        with LOCK:
            if isinstance(payload.get("menuExtras"), dict):
                STATE["menuExtras"] = payload["menuExtras"]
                threading.Thread(target=supabase_sync_state_key, args=("menuExtras", STATE["menuExtras"]), daemon=True).start()
            if isinstance(payload.get("menus"), dict):
                STATE["menus"] = payload["menus"]
                threading.Thread(target=supabase_sync_state_key, args=("menus", STATE["menus"]), daemon=True).start()
            if isinstance(payload.get("profiles"), dict):
                STATE["profiles"] = {**STATE["profiles"], **payload["profiles"]}
                threading.Thread(target=supabase_sync_state_key, args=("profiles", STATE["profiles"]), daemon=True).start()
            if isinstance(payload.get("campaigns"), list):
                STATE["campaigns"] = payload["campaigns"]
                threading.Thread(target=supabase_sync_state_key, args=("campaigns", STATE["campaigns"]), daemon=True).start()
            if isinstance(payload.get("orders"), list):
                if payload.get("replaceOrders"):
                    STATE["orders"] = [normalize_order(row) for row in payload["orders"] if row.get("id")]
                else:
                    by_id = {row.get("id"): row for row in STATE["orders"] if row.get("id")}
                    for row in payload["orders"]:
                        if row.get("id"):
                            by_id[row["id"]] = normalize_order(row)
                    STATE["orders"] = list(by_id.values())
            snap = snapshot_state()
        broadcast({"type": "snapshot", "state": snap})
        self.send_json({"ok": True})

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path in ("/api/order", "/api/orders"):
            order = self.read_json()
            if not isinstance(order, dict) or not order.get("restaurantId"):
                self.send_error(400)
                return
            row = upsert_order(order)
            self.send_json({"ok": True, "id": row.get("id"), "trigger_alarm": row.get("trigger_alarm")})
            return
        if path in ("/api/orders/location", "/api/order/location"):
            payload = self.read_json()
            if not payload.get("id"):
                self.send_error(400)
                return
            payload["source"] = payload.get("source") or "ios"
            with LOCK:
                existing = next((o for o in STATE["orders"] if o.get("id") == payload.get("id")), None)
                existing_status = (existing or {}).get("status")
                rest_id = (existing or {}).get("restaurantId") or payload.get("restaurantId") or "mcd-samsun"

            # Eğer koordinat gönderilmişse ve sabit meters gönderilmemişse Haversine ile hesapla
            if (
                payload.get("latitude") is not None
                and payload.get("longitude") is not None
                and payload.get("meters") is None
            ):
                rlat, rlng = restaurant_pin(rest_id)
                payload["meters"] = haversine_meters(
                    float(payload["latitude"]),
                    float(payload["longitude"]),
                    rlat,
                    rlng,
                )

            if existing_status in ("iletildi", "kabul", "hazir", "teslim", "iptal"):
                payload.pop("status", None)
            elif int(payload.get("meters") if payload.get("meters") is not None else START_M) == 0:
                payload["status"] = "kapıda"
            row = upsert_order(payload)
            self.send_json({
                "ok": True,
                "id": row.get("id"),
                "meters": row.get("meters"),
                "eta_seconds": row.get("eta_seconds"),
                "status": row.get("status"),
                "trigger_alarm": row.get("trigger_alarm"),
            })
            return
        if path in ("/api/orders/status", "/api/order/status"):
            payload = self.read_json()
            if not payload.get("id") or not payload.get("status"):
                self.send_error(400)
                return
            patch = {"id": payload["id"], "status": payload["status"]}
            if payload.get("cancelReason"):
                patch["cancelReason"] = str(payload["cancelReason"])
            if payload.get("prepMinutes") is not None:
                patch["prepMinutes"] = int(payload["prepMinutes"])
            row = upsert_order(patch)
            self.send_json({"ok": True, "id": row.get("id"), "status": row.get("status"), "cancelReason": row.get("cancelReason")})
            return
        if path in ("/api/orders/clear", "/api/order/clear"):
            payload = self.read_json()
            restaurant_id = payload.get("restaurantId")
            mode = payload.get("mode") or "completed"
            removed_ids = []
            with LOCK:
                kept = []
                for o in STATE["orders"]:
                    same_rest = (not restaurant_id) or (o.get("restaurantId") == restaurant_id)
                    if mode == "all" and same_rest:
                        removed_ids.append(o.get("id"))
                    elif mode != "all" and same_rest and o.get("status") in ("teslim", "iptal"):
                        removed_ids.append(o.get("id"))
                    else:
                        kept.append(o)
                STATE["orders"] = kept
                snap = snapshot_state()
            if removed_ids:
                threading.Thread(target=supabase_delete_orders, args=(removed_ids,), daemon=True).start()
            broadcast({"type": "snapshot", "state": snap})
            self.send_json({"ok": True, "removed": len(removed_ids), "orders": snap["orders"]})
            return
        if path in ("/api/orders/drive", "/api/order/drive"):
            payload = self.read_json()
            action = payload.get("action")
            if not payload.get("id") or action not in ("speaker", "match", "door", "seen"):
                self.send_error(400)
                return
            with LOCK:
                row = apply_drive(payload["id"], action, int(payload.get("speaker") or 0))
                if not row:
                    self.send_error(404)
                    return
                row_copy = dict(row)
            threading.Thread(target=supabase_sync_order, args=(row_copy,), daemon=True).start()
            broadcast({
                "type": "order.upsert",
                "order": row_copy,
                "trigger_alarm": bool(row_copy.get("trigger_alarm")),
            })
            if action == "door":
                broadcast({"type": "order.door", "order": row_copy, "trigger_alarm": True})
            self.send_json({
                "ok": True,
                "id": row_copy.get("id"),
                "speaker": row_copy.get("speaker"),
                "lane": row_copy.get("lane"),
                "stall": row_copy.get("stall"),
                "speakerMatched": row_copy.get("speakerMatched"),
                "atDoor": row_copy.get("atDoor"),
                "seenCar": row_copy.get("seenCar"),
                "status": row_copy.get("status"),
                "meters": row_copy.get("meters"),
                "trigger_alarm": row_copy.get("trigger_alarm"),
            })
            return
        if path in ("/api/auth", "/api/auth/restaurant", "/api/auth/customer"):
            ip = self.client_address[0] if self.client_address else "local"
            if not rate_ok(ip):
                self.send_error(429)
                return
            payload = self.read_json()
            seed = load_json(SEED, {})
            email = str(payload.get("email") or payload.get("identifier") or "").strip().lower()
            password = str(payload.get("password") or "")
            staff = payload.get("staffRole") or "yonetici"
            for row in seed.get("restaurants") or []:
                if row.get("email", "").lower() == email and row.get("password") == password:
                    self.send_json({
                        "ok": True,
                        "role": "restaurant",
                        "staffRole": staff if staff in ("yonetici", "mutfak", "kasiyer") else "yonetici",
                        "id": row.get("id"),
                        "city": seed.get("city") or "Samsun",
                    })
                    return
            demo = (seed.get("demo") or {}).get("customer") or {}
            if demo.get("email", "").lower() == email and demo.get("password") == password:
                self.send_json({"ok": True, "role": "customer", "id": "cust-demo", "city": seed.get("city") or "Samsun"})
                return
            self.send_error(401)
            return
        if path == "/api/campaigns":
            campaign = self.read_json()
            with LOCK:
                STATE["campaigns"].insert(0, campaign)
                campaigns = list(STATE["campaigns"])
            threading.Thread(target=supabase_sync_state_key, args=("campaigns", campaigns), daemon=True).start()
            broadcast({"type": "campaigns", "campaigns": campaigns})
            self.send_json({"ok": True})
            return
        self.send_error(404)

    def do_PATCH(self):
        self.do_POST()

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8") if length else "{}"
        return json.loads(raw)

    def send_json(self, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("[cloud]", fmt % args, flush=True)


def approach_loop():
    while True:
        time.sleep(1.0)
        changed = []
        with LOCK:
            for order in STATE["orders"]:
                if order.get("source") == "ios":
                    continue
                if order.get("status") in ("teslim", "iptal"):
                    continue
                meters = int(order.get("meters") or 0)
                if meters <= 0:
                    continue
                order["meters"] = max(0, meters - 10)
                lat, lng = interpolate_coords(order.get("restaurantId"), order["meters"])
                order["latitude"] = lat
                order["longitude"] = lng
                if order["meters"] == 0 and order.get("status") not in ("iletildi", "kabul", "hazir"):
                    order["status"] = "kapıda"
                    order["atDoor"] = True
                order.update(normalize_order(order))
                changed.append(dict(order))
        for row in changed:
            threading.Thread(target=supabase_sync_order, args=(row,), daemon=True).start()
            broadcast({
                "type": "order.upsert",
                "order": row,
                "trigger_alarm": bool(row.get("trigger_alarm")),
            })
            if int(row.get("meters") or 0) == 0:
                broadcast({"type": "order.door", "order": row, "trigger_alarm": True})


if __name__ == "__main__":
    supabase_Bootstrap()
    threading.Thread(target=approach_loop, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"konumumyemek.com cloud aktif -> http://0.0.0.0:{PORT}/panel.html", flush=True)
    server.serve_forever()
