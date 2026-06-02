# HatcheryOS.MY — CPF Malaysia Upstream Management

Web application for managing the upstream hatching egg pipeline — from farm collection to hatchery setting — feeding into the existing DOC Tracker system.

## System Overview

```
Farm egg production
  → Cool room stock (HatcheryOS)
  → Egg setting / incubation (HatcheryOS)
  → Hatch forecast → auto-syncs to DOC Tracker hatchery_estimates
  → DOC production tracking (DOC Tracker ← existing system)
  → Customer delivery (DOC Tracker)
```

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla HTML/CSS/JS (single file, no build step) |
| Backend | Supabase (shared with DOC Tracker) |
| Auth | Supabase Auth — same credentials as DOC Tracker |
| Hosting | GitHub Pages |
| Realtime | Supabase Realtime subscriptions |

## Setup

### Step 1 — Create Supabase tables

Run `supabase_setup.sql` in the **Supabase SQL Editor** of the existing DOC Tracker project:

```
Project: ncnppcmlxdaabuwkcbtm (same as DOC Tracker)
```

This creates 3 new tables without touching existing DOC Tracker tables:
- `farm_egg_plan` — weekly farm HE production + external buy planning
- `egg_lots` — individual HE lot tracking (farm → cool room → hatchery)
- `egg_settings` — incubation batches with hatch date auto-calculation

### Step 2 — Deploy to GitHub Pages

1. Create a **new GitHub repo**: `cpf-hatchery-os` (separate from DOC Tracker repo)
2. Push `index.html` to the `main` branch
3. Enable GitHub Pages: **Settings → Pages → Source: main branch → / (root)**
4. Site will be live at: `https://[your-org].github.io/cpf-hatchery-os/`

### Step 3 — Login

Use the same email/password as your DOC Tracker account.  
No new accounts needed — Supabase Auth is shared.

## Features

### ✅ Available Now
| Module | Description |
|---|---|
| **Dashboard** | KPI overview, alerts for aging eggs, upcoming hatches |
| **Farm Supply Plan** | Weekly HE production per farm, gap analysis, external buy planning |
| **HE Delivery** | Record egg lots arriving from farm with breed, WOP, quantity |
| **Cool Room Stock** | Live inventory with storage decay calculation |
| **Setting Schedule** | Initiate incubation, timeline progress, hatch calendar |
| **Candling Results** | Enter fertility data at day 18 |
| **DOC Forecast** | 8-week forward forecast, auto-syncs to DOC Tracker estimates |
| **Hatchery Capacity** | Utilisation % per hatchery |
| **Breed Standards** | Ross 308, Cobb 500, Hubbard hatchability tables |
| **Storage Research** | Scientific decay model, interactive calculator |
| **Reports** | Hatch history, performance vs standard |

### 🔗 DOC Tracker Integration
When an egg setting is confirmed, `forecast_doc` automatically syncs to  
`hatchery_estimates` in DOC Tracker via a Supabase database trigger.  
No manual entry needed in DOC Tracker for the estimate.

### 📋 Planned (Phase 2)
- Import farm plan data from Excel Masterplan
- Customer order demand vs supply gap view
- Export reports to PDF/Excel

## Data Model

```
farm_egg_plan          egg_lots               egg_settings
─────────────          ────────               ────────────
week_no                lot_id                 set_id
week_end_date          farm → hatchery        lot_id (FK)
farm_rantau            breed, wop             hatchery, breed, wop
farm_sg_sayong         qty_received           set_date
farm_ulu_tiram         stock_remaining        hatch_date (+21d, generated)
farm_kluang            recv_date              hatch_week_no
farm_sg_siput          is_external            adj_hatchability
total_farm_he          status                 forecast_doc
plan_buy_he                                   actual_doc
actual_buy_he                                 status
```

## Key Business Logic

- **Hatch date** = set_date + 21 days (auto-calculated)
- **Adjusted hatchability** = breed standard% − storage decay%
- **Storage decay**: −0.2%/day days 1–7, −0.5%/day days 8+, extra −0.1%/day for WOP>38 after day 5
- **Forecast DOC** = set_qty × adj_hatchability / 100
- **Egg set this week → DOC hatches week +3** (key upstream→downstream link)

## Hatchery Reference

| Hatchery | Type | Weekly Capacity |
|---|---|---|
| Chengkau | Single Stage | 774,144 |
| Kluang | Single Stage | 345,600 |
| K.Kangsar | Multi Stage | 622,080 |
| Sg. Sayong | Multi Stage | 311,040 |
| **Total** | | **2,052,864** |

## Files

```
cpf-hatchery-os/
├── index.html          ← entire app (single file, no dependencies except Supabase CDN)
├── supabase_setup.sql  ← run once in Supabase SQL Editor
└── README.md
```
# HatcheryOS.MY
A Hatchery OS management for CP Malaysia
