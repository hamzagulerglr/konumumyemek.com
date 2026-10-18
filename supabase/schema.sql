-- =============================================================================
-- konumumyemek.com · Supabase (PostgreSQL) Production Schema
-- Tablolar: orders, live_tracking, restaurant_state
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. ORDERS TABLOSU (Ana Sipariş Kayıtları)
CREATE TABLE IF NOT EXISTS public.orders (
    id              TEXT PRIMARY KEY,
    restaurant_id   TEXT NOT NULL,
    customer_id     TEXT,
    driver_name     TEXT NOT NULL DEFAULT '',
    customer_name   TEXT NOT NULL DEFAULT '',
    plate           TEXT NOT NULL,
    items           TEXT NOT NULL,
    payment_method  TEXT NOT NULL DEFAULT 'Metropol Card',
    total_amount    INTEGER NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    order_status    TEXT NOT NULL DEFAULT 'iletildi'
                    CHECK (order_status IN ('iletildi', 'kabul', 'hazir', 'yolda', 'kapıda', 'kapida', 'teslim', 'iptal')),
    cancel_reason   TEXT DEFAULT '',
    prep_minutes    INTEGER DEFAULT 0,
    lane            TEXT DEFAULT '',
    stall           INTEGER NOT NULL DEFAULT 0,
    speaker         INTEGER NOT NULL DEFAULT 0,
    speaker_matched BOOLEAN NOT NULL DEFAULT FALSE,
    at_door         BOOLEAN NOT NULL DEFAULT FALSE,
    seen_car        BOOLEAN NOT NULL DEFAULT FALSE,
    source          TEXT NOT NULL DEFAULT 'ios',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status
    ON public.orders (restaurant_id, order_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_plate
    ON public.orders (plate);


-- 2. LIVE_TRACKING TABLOSU (Anlık Araç Konumu, Mesafe, ETA ve Alarm Durumu)
CREATE TABLE IF NOT EXISTS public.live_tracking (
    order_id          TEXT PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
    restaurant_id     TEXT NOT NULL,
    plate             TEXT NOT NULL,
    latitude          DOUBLE PRECISION NOT NULL,
    longitude         DOUBLE PRECISION NOT NULL,
    distance_meters   INTEGER NOT NULL DEFAULT 1400 CHECK (distance_meters >= 0),
    eta_seconds       INTEGER NOT NULL DEFAULT 140 CHECK (eta_seconds >= 0),
    order_status      TEXT NOT NULL DEFAULT 'iletildi'
                      CHECK (order_status IN ('iletildi', 'kabul', 'hazir', 'yolda', 'kapıda', 'kapida', 'teslim', 'iptal')),
    trigger_alarm     BOOLEAN NOT NULL DEFAULT FALSE,
    at_door           BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_tracking_restaurant
    ON public.live_tracking (restaurant_id, distance_meters ASC);


-- 3. RESTAURANT_STATE TABLOSU (Menü/86, Kampanyalar ve Şube Açık/Kapalı/Saat Profilleri)
CREATE TABLE IF NOT EXISTS public.restaurant_state (
    key        TEXT PRIMARY KEY,
    payload    JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 4. OTOMATİK UPDATED_AT TRIGGER FONKSİYONU
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_orders_updated_at ON public.orders;
CREATE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS trg_live_tracking_updated_at ON public.live_tracking;
CREATE TRIGGER trg_live_tracking_updated_at
    BEFORE UPDATE ON public.live_tracking
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


-- 5. SUPABASE REALTIME YAYINI (Opsiyonel Doğrudan Dinleme İçin)
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_tracking;
