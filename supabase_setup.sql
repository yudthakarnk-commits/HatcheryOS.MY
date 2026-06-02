-- ============================================================
-- HatcheryOS — New Tables for Egg Management System
-- Run this in Supabase SQL Editor (same project as DOC Tracker)
-- Tables: farm_egg_plan, egg_lots, egg_settings
-- Does NOT touch existing DOC Tracker tables
-- ============================================================

-- 1. FARM EGG PLAN
-- Weekly egg production per farm + external buy planning
-- Source: Excel Masterplan columns C-I
CREATE TABLE IF NOT EXISTS farm_egg_plan (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  week_no         integer NOT NULL,
  week_end_date   date NOT NULL,
  farm_rantau     integer DEFAULT 0,
  farm_sg_sayong  integer DEFAULT 0,
  farm_ulu_tiram  integer DEFAULT 0,
  farm_kluang     integer DEFAULT 0,
  farm_sg_siput   integer DEFAULT 0,
  total_farm_he   integer GENERATED ALWAYS AS (
    farm_rantau + farm_sg_sayong + farm_ulu_tiram + farm_kluang + farm_sg_siput
  ) STORED,
  plan_buy_he     integer DEFAULT 0,
  actual_buy_he   integer DEFAULT 0,
  notes           text,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now(),
  UNIQUE(week_no, week_end_date)
);

-- 2. EGG LOTS
-- Individual egg lot tracking: farm → cool room → hatchery
CREATE TABLE IF NOT EXISTS egg_lots (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lot_id          text UNIQUE NOT NULL,           -- e.g. LOT-0001
  farm            text NOT NULL,                  -- Rantau, Kluang, etc.
  hatchery        text NOT NULL,                  -- Chengkau, Kluang, K.Kangsar, Sg.Sayong
  breed           text NOT NULL,                  -- Ross 308, Cobb 500, Hubbard
  wop             integer NOT NULL,               -- Week of Production
  qty_received    integer NOT NULL,
  stock_remaining integer NOT NULL,
  recv_date       date NOT NULL,
  is_external     boolean DEFAULT false,          -- true = bought from external source
  external_source text,                           -- supplier name if external
  status          text DEFAULT 'cool_room'        -- cool_room | incubating | candling | transfer | completed
    CHECK (status IN ('cool_room','incubating','candling','transfer','completed')),
  week_no         integer,                        -- links to farm_egg_plan
  notes           text,
  created_by      uuid REFERENCES auth.users(id),
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- 3. EGG SETTINGS
-- When eggs are moved from cool room into incubators
-- KEY: hatch_date = set_date + 21 days → feeds hatchery_estimates in DOC Tracker
CREATE TABLE IF NOT EXISTS egg_settings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id              text UNIQUE NOT NULL,       -- e.g. SET-0001
  lot_id              uuid REFERENCES egg_lots(id),
  hatchery            text NOT NULL,
  breed               text NOT NULL,
  wop                 integer NOT NULL,
  storage_days        integer NOT NULL,           -- days in cool room before setting
  set_qty             integer NOT NULL,
  set_date            date NOT NULL,
  hatch_date          date GENERATED ALWAYS AS (set_date + interval '21 days') STORED,
  hatch_week_no       integer,                    -- week number of hatch_date (auto-calc via trigger)
  std_hatchability    numeric(5,2),               -- from breed standard table
  storage_decay       numeric(5,2),               -- calculated decay %
  adj_hatchability    numeric(5,2),               -- std - decay
  forecast_doc        integer,                    -- set_qty * adj_hatchability / 100
  -- Candling results
  candling_date       date,
  candling_clear      integer,
  candling_infertile  integer,
  candling_dead       integer,
  -- Actual hatch results
  actual_doc          integer,
  actual_hatch_pct    numeric(5,2),
  status              text DEFAULT 'incubating'
    CHECK (status IN ('incubating','candling','transfer','completed')),
  notes               text,
  created_by          uuid REFERENCES auth.users(id),
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now()
);

-- ============================================================
-- INDEXES for performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_farm_egg_plan_week ON farm_egg_plan(week_no);
CREATE INDEX IF NOT EXISTS idx_egg_lots_hatchery ON egg_lots(hatchery);
CREATE INDEX IF NOT EXISTS idx_egg_lots_status ON egg_lots(status);
CREATE INDEX IF NOT EXISTS idx_egg_lots_recv_date ON egg_lots(recv_date);
CREATE INDEX IF NOT EXISTS idx_egg_settings_hatch_date ON egg_settings(hatch_date);
CREATE INDEX IF NOT EXISTS idx_egg_settings_hatchery ON egg_settings(hatchery);
CREATE INDEX IF NOT EXISTS idx_egg_settings_status ON egg_settings(status);
CREATE INDEX IF NOT EXISTS idx_egg_settings_hatch_week ON egg_settings(hatch_week_no);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- Matches pattern of existing DOC Tracker tables
-- ============================================================
ALTER TABLE farm_egg_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE egg_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE egg_settings ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read
CREATE POLICY "Authenticated read farm_egg_plan"
  ON farm_egg_plan FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated read egg_lots"
  ON egg_lots FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated read egg_settings"
  ON egg_settings FOR SELECT TO authenticated USING (true);

-- All authenticated users can insert/update/delete
-- (tighten later based on role if needed)
CREATE POLICY "Authenticated write farm_egg_plan"
  ON farm_egg_plan FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated write egg_lots"
  ON egg_lots FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated write egg_settings"
  ON egg_settings FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ============================================================
-- TRIGGER: auto-set hatch_week_no on egg_settings insert/update
-- ============================================================
CREATE OR REPLACE FUNCTION calc_hatch_week()
RETURNS TRIGGER AS $$
BEGIN
  -- Simple ISO week number of hatch_date
  NEW.hatch_week_no := EXTRACT(WEEK FROM (NEW.set_date + interval '21 days'))::integer;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_calc_hatch_week ON egg_settings;
CREATE TRIGGER trg_calc_hatch_week
  BEFORE INSERT OR UPDATE ON egg_settings
  FOR EACH ROW EXECUTE FUNCTION calc_hatch_week();

-- ============================================================
-- TRIGGER: sync forecast_doc → hatchery_estimates (DOC Tracker)
-- When egg_settings is inserted/updated with a forecast_doc,
-- upsert into hatchery_estimates so DOC Tracker sees it.
-- Only runs if hatchery_estimates table exists.
-- ============================================================
CREATE OR REPLACE FUNCTION sync_to_hatchery_estimates()
RETURNS TRIGGER AS $$
BEGIN
  -- Only sync if forecast is available and status is active
  IF NEW.forecast_doc IS NOT NULL AND NEW.status != 'completed' THEN
    INSERT INTO hatchery_estimates (hatchery, week_no, estimate_total, period_type, created_at)
    VALUES (NEW.hatchery, NEW.hatch_week_no, NEW.forecast_doc, 'week', now())
    ON CONFLICT (hatchery, week_no, period_type)
    DO UPDATE SET
      estimate_total = EXCLUDED.estimate_total,
      created_at = now();
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- If hatchery_estimates doesn't have the right unique constraint, skip silently
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_estimates ON egg_settings;
CREATE TRIGGER trg_sync_estimates
  AFTER INSERT OR UPDATE ON egg_settings
  FOR EACH ROW EXECUTE FUNCTION sync_to_hatchery_estimates();

-- ============================================================
-- VERIFY: check tables were created
-- ============================================================
SELECT table_name, pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) AS size
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('farm_egg_plan','egg_lots','egg_settings','doc_records','hatchery_estimates')
ORDER BY table_name;
