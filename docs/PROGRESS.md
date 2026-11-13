# akwe — Implementation Progress

> Living checklist. If work stops midway, resume from the first unchecked item.
> Each phase ends with a commit on branch `claude/eloquent-hamilton-vm5fcu`.

## Key decisions (made up front, don't re-litigate)

| Area | Decision | Why |
|---|---|---|
| iOS | Swift 6 / SwiftUI, iOS 17+, `@Observable` | Native motion, widgets, Sign in with Apple, LinkKit |
| Project file | **XcodeGen** (`ios/project.yml`) → run `xcodegen` on the Mac | No .xcodeproj merge pain; generated from text |
| Swift mode | Swift 6 compiler in **Swift 5 language mode** for app targets (avoids strict-concurrency churn); AkweKit types are `Sendable` | Fewer surprises on first build |
| Domain logic | Local Swift package **`ios/Packages/AkweKit`** (Foundation only) | Unit-testable on Linux CI and macOS; app + widget share it |
| Local cache | Codable JSON snapshot in the App Group container | Simple, shared with widgets; server is source of truth |
| Backend | **Supabase** (Postgres + RLS, Auth, Edge Functions in Deno/TS, pg_cron) | Auth with Apple, secrets server-side, cheap |
| Auth | Sign in with Apple only → `supabase.auth.signInWithIdToken(provider: .apple)` | Product requirement |
| Plaid | Link token + public-token exchange + `/transactions/sync` (cursor) + webhooks, on the server only | Plaid secret and access tokens never reach the phone |
| Access tokens | Stored in `public.plaid_secrets` with RLS on, **no policies** and grants revoked → only the service role (edge functions) can read it | PostgREST can only reach exposed schemas, so a non-exposed schema would block the functions too |
| Enrichment | Done server-side at sync: payment method, transfer pairing, card-settlement matching, category mapping, user rules | One place, consistent across devices |
| Stats | Computed on device (AkweKit) from synced transactions | Instant period switching, testable |
| Notifications | Server evaluates after each sync (budgets 80/100 %, goal milestones/reached, bills due, re-auth) → APNs (token-based .p8) | Works when the app is closed |
| FX | `fx_rates` table filled daily from frankfurter.app (ECB, no key); balances at today's rate, transactions at their date's rate | Free, reliable for EUR/USD/CAD/GBP/CHF |
| i18n | `Localizable.xcstrings` (en + fr), English text as keys; formatters via `Locale` | Requirement |
| Theme | Semantic color tokens with light/dark variants in code (`Theme.swift`) | Requirement, matches design canvas |

Design reference: https://claude.ai/artifact/H2gQvgcEXUZLpBW9YVKo94 · Feature spec: `docs/FEATURES.md`

## Phases

- [x] **0. Scaffolding** — repo layout, README, .gitignore, this file
- [x] **1. Database** — migrations: schema, RLS, default categories/pockets, triggers, cron
- [x] **2. Backend shared logic + tests** — payment method parser (US/CA/FR/UK/DE), transfer pairing, card settlement, category mapping, rules, pay periods, FX
- [x] **3. Edge functions** — plaid-link-token, plaid-exchange, plaid-sync, plaid-webhook, fx-refresh, notify, goal-invite / goal-join, delete-account
- [x] **4. AkweKit** — models, Money/FX, pay period engine, stats, budgets, goals projection, safe-to-spend, formatting + tests
- [ ] **5. App shell** — project.yml, theme, components, localization, AppModel, Supabase client, Sign in with Apple, Face ID lock, tab bar
- [ ] **6. Onboarding** — welcome, link banks (LinkKit), first sync, pay schedule
- [ ] **7. Home & Activity** — home, activity feed + filters/search, transaction detail, review inbox, rules
- [ ] **8. Insights & pockets** — insights (period switcher, curve, tiles, pockets), pocket detail, manage pockets, bills & subscriptions
- [ ] **9. Plan** — goals, goal detail, new goal, forecast/what-if, shared goals (invite/join)
- [ ] **10. Settings** — alerts, display currency, appearance, accounts & cards, re-auth, delete account
- [ ] **11. Widgets & push** — widget extension (small/medium/large/lock screen), APNs registration
- [ ] **12. Setup guide** — README: Supabase, Plaid, Apple (Sign in with Apple, APNs key, App Group), xcodegen, running tests

## Log

(append one line per completed step: date · phase · what · notes)
- 2026-11-13 · 0 · repo layout, .gitignore, PROGRESS.md
- 2026-11-13 · 1 · 4 migrations (schema, RLS, defaults trigger, cron). Validated on Postgres 16 with Supabase stubs: defaults seeded (7 pockets / 30 categories), cross-user isolation, shared-goal privacy view, server-only columns protected
- 2026-11-13 · 2 · `_shared/` normalize, paymentMethod, categorize, kinds (transfers/card payments/deferred settlement), payPeriod, fx — `deno test tests/` 9/9 green
- 2026-11-13 · 3 · Edge functions: plaid-link-token (incl. update mode, 4-bank cap, OAuth redirect), plaid-exchange (dedupe same bank, first sync), plaid-sync (user or cron-all), plaid-webhook (ES256 JWT verification, item errors → re-auth push), plaid-remove-item, fx-refresh (frankfurter, 2y backfill, XOF peg), notify (daily + evaluate), goal-action (invite/preview/join/cheer/check/leave), delete-account. `_shared/syncCore.ts` (cursor sync, pending→posted carry-over of user edits, transfer pairing, recurring streams, pay-schedule auto-detect), `_shared/notifyCore.ts` (budgets 80/100 %, goal milestones/reached, bills due, payday summary, en/fr strings, dedupe via notification_log), `_shared/apns.ts`. Migration 5: goal triggers. `deno check` clean, tests 9/9, migrations re-validated
- 2026-11-13 · 4 · AkweKit: Day/DayRange, Models (fallback enums), PaySchedule periods + detection (mirrors TS), RateBook FX + MoneyFormat, MerchantNormalizer (byte-for-byte same keys as server), Ledger, Stats (summary, pockets w/ previous, cumulative + average curve, history, weekday pattern), Planning (budget status, safe-to-spend, goal progress/status, what-if arrival), WidgetSnapshot + AppGroup. `swift test` 16/16 on Linux (Swift 6.0.3)
