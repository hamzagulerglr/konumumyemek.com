#!/usr/bin/env node
/**
 * konumumyemek.com — Canlı Supabase `live_tracking` Test Simülatörü
 * Sahte Müşteri Konumu:
 *   Latitude  = 41.3320
 *   Longitude = 36.2730
 *   Status    = "Yolda" (< 500m yaklaşım alarmını tetikler)
 */

const fs = require("fs");
const path = require("path");

const SUPABASE_PROJECT_ID = "hetcihydnkgbuglsuzcs";
const SUPABASE_URL = process.env.SUPABASE_URL || `https://${SUPABASE_PROJECT_ID}.supabase.co`;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "sb_publishable_Xh8V52jmvs1JFpKX7v8SuA_SFk1DA0Z";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const SUPABASE_KEY = SUPABASE_ANON_KEY || SUPABASE_SERVICE_ROLE_KEY;

const FAKE_LOCATION = {
  order_id: "sim-500m-" + Date.now(),
  restaurant_id: "mcd-samsun",
  plate: "34 KNM 55",
  driver_name: "Ahmet Yılmaz",
  customer_name: "Ahmet Yılmaz",
  items: "1× Big Mac Menü, 1× Büyük Boy Patates, 1× Coca-Cola",
  payment_method: "Metropol Card",
  total_amount: 340,
  latitude: 41.3320,
  longitude: 36.2730,
  status: "Yolda",
  order_status: "yolda",
  distance_meters: 320,
  eta_seconds: 38,
  trigger_alarm: true,
  at_door: false,
  updated_at: new Date().toISOString()
};

async function pushToSupabaseCloud() {
  const headers = {
    "Content-Type": "application/json",
    apikey: SUPABASE_KEY,
    Authorization: `Bearer ${SUPABASE_KEY}`,
    Prefer: "resolution=merge-duplicates,return=representation"
  };

  // 1. `orders` tablosuna ana sipariş kaydını ilet
  await fetch(`${SUPABASE_URL}/rest/v1/orders?on_conflict=id`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      id: FAKE_LOCATION.order_id,
      restaurant_id: FAKE_LOCATION.restaurant_id,
      driver_name: FAKE_LOCATION.driver_name,
      customer_name: FAKE_LOCATION.customer_name,
      plate: FAKE_LOCATION.plate,
      items: FAKE_LOCATION.items,
      payment_method: FAKE_LOCATION.payment_method,
      total_amount: FAKE_LOCATION.total_amount,
      order_status: FAKE_LOCATION.order_status,
      at_door: false,
      source: "test_simulator.js",
      updated_at: FAKE_LOCATION.updated_at
    })
  });

  // 2. `live_tracking` tablosuna sahte müşteri konumunu (41.3320, 36.2730, Status="Yolda") bas
  const res = await fetch(`${SUPABASE_URL}/rest/v1/live_tracking?on_conflict=order_id`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      order_id: FAKE_LOCATION.order_id,
      restaurant_id: FAKE_LOCATION.restaurant_id,
      plate: FAKE_LOCATION.plate,
      latitude: FAKE_LOCATION.latitude,
      longitude: FAKE_LOCATION.longitude,
      distance_meters: FAKE_LOCATION.distance_meters,
      eta_seconds: FAKE_LOCATION.eta_seconds,
      order_status: FAKE_LOCATION.order_status,
      trigger_alarm: true,
      at_door: false,
      updated_at: FAKE_LOCATION.updated_at
    })
  });

  // 3. Supabase Realtime Broadcast kanalına da doğrudan paketi fırlat
  await fetch(`${SUPABASE_URL}/realtime/v1/api/broadcast`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`
    },
    body: JSON.stringify({
      messages: [
        {
          topic: "konumum-kds-realtime",
          event: "order.upsert",
          payload: {
            type: "order.upsert",
            trigger_alarm: true,
            order: {
              id: FAKE_LOCATION.order_id,
              restaurantId: FAKE_LOCATION.restaurant_id,
              driverName: FAKE_LOCATION.driver_name,
              customer: FAKE_LOCATION.customer_name,
              plate: FAKE_LOCATION.plate,
              items: FAKE_LOCATION.items,
              payment: FAKE_LOCATION.payment_method,
              total: FAKE_LOCATION.total_amount,
              latitude: FAKE_LOCATION.latitude,
              longitude: FAKE_LOCATION.longitude,
              meters: FAKE_LOCATION.distance_meters,
              distance_meters: FAKE_LOCATION.distance_meters,
              eta_seconds: FAKE_LOCATION.eta_seconds,
              status: "yolda",
              trigger_alarm: true,
              atDoor: false,
              updatedAt: FAKE_LOCATION.updated_at
            }
          }
        }
      ]
    })
  }).catch(() => {});

  return res.ok;
}

async function pushToActiveKdsRadar() {
  const kdsOrder = {
    id: FAKE_LOCATION.order_id,
    restaurantId: FAKE_LOCATION.restaurant_id,
    driverName: FAKE_LOCATION.driver_name,
    customer: FAKE_LOCATION.customer_name,
    plate: FAKE_LOCATION.plate,
    items: FAKE_LOCATION.items,
    payment: FAKE_LOCATION.payment_method,
    total: FAKE_LOCATION.total_amount,
    latitude: FAKE_LOCATION.latitude,
    longitude: FAKE_LOCATION.longitude,
    meters: FAKE_LOCATION.distance_meters,
    distance_meters: FAKE_LOCATION.distance_meters,
    eta_seconds: FAKE_LOCATION.eta_seconds,
    status: "yolda",
    orderStatusDisplay: FAKE_LOCATION.status,
    trigger_alarm: true,
    atDoor: false,
    source: "supabase-live_tracking",
    updatedAt: FAKE_LOCATION.updated_at
  };

  // Canlı KDS sunucu soketine ve çalışma zamanı önbelleğine anında ilet
  try {
    await fetch("http://127.0.0.1:8765/api/order", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(kdsOrder)
    });
    await fetch("http://127.0.0.1:8765/api/orders/location", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        id: FAKE_LOCATION.order_id,
        latitude: FAKE_LOCATION.latitude,
        longitude: FAKE_LOCATION.longitude,
        meters: FAKE_LOCATION.distance_meters,
        status: "yolda",
        source: "supabase-live_tracking"
      })
    });
  } catch { /* ignore */ }

  try {
    const runtimePath = path.join(__dirname, "web", "data", "runtime.json");
    if (fs.existsSync(runtimePath)) {
      const rt = JSON.parse(fs.readFileSync(runtimePath, "utf8"));
      rt.orders = Array.isArray(rt.orders) ? rt.orders : [];
      rt.orders = rt.orders.filter((o) => o.id !== kdsOrder.id);
      rt.orders.unshift(kdsOrder);
      fs.writeFileSync(runtimePath, JSON.stringify(rt, null, 2), "utf8");
    }
  } catch { /* ignore */ }
}

async function main() {
  console.log("====================================================");
  console.log("🚀 konumumyemek.com · Supabase `live_tracking` Simülatörü");
  console.log(`🌐 SUPABASE_URL : ${SUPABASE_URL}`);
  console.log(`📍 Latitude     : ${FAKE_LOCATION.latitude.toFixed(4)}`);
  console.log(`📍 Longitude    : ${FAKE_LOCATION.longitude.toFixed(4)}`);
  console.log(`🚗 Status       : "${FAKE_LOCATION.status}" (Mesafe: ${FAKE_LOCATION.distance_meters} m < 500 m)`);
  console.log("====================================================\n");

  let cloudSynced = false;
  try {
    cloudSynced = await pushToSupabaseCloud();
  } catch {
    cloudSynced = false;
  }

  await pushToActiveKdsRadar();

  console.log("✅ `live_tracking` verisi başarıyla fırlatıldı!");
  console.log("📦 Gönderilen Payload:");
  console.log(
    JSON.stringify(
      {
        table: "public.live_tracking",
        order_id: FAKE_LOCATION.order_id,
        plate: FAKE_LOCATION.plate,
        latitude: FAKE_LOCATION.latitude,
        longitude: FAKE_LOCATION.longitude,
        status: FAKE_LOCATION.status,
        distance_meters: FAKE_LOCATION.distance_meters,
        trigger_alarm: FAKE_LOCATION.trigger_alarm,
        cloud_synced: cloudSynced
      },
      null,
      2
    )
  );
  console.log("\n🚨 Mutfak radarı güncellendi ve <500 metre sesli yaklaşım alarmı tetiklendi!");
}

main();
