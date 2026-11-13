# akwe — Feature Spec (iOS, Plaid)

> Status: **Draft for review.** No code yet. Once the feature list is locked, the next pass covers flows, screen design, motion and the design system.

App name: **akwe** (*akwɛ* = money in Fongbe). Logo: a cowrie shell, historically used as money in Dahomey, on an indigo app icon with a mint coin.

## 1. Vision

A personal money cockpit: every linked account in one place, every transaction understood, and a clear answer to three questions at any moment:

1. **Where did my money go?** (this pay period, this month, over time)
2. **How much can I still spend?** (before the next paycheck)
3. **Am I on track for what I'm planning?** (goals, big purchases)

Design language: Revolut-style — dark-first, big numbers, glassy cards, fluid spring animations, haptics everywhere, one-thumb navigation.

## 2. Key constraints to know up front

| Constraint | What it means for the product |
|---|---|
| **Plaid is read-only** (Transactions/Balance products) | The app *observes* money, it doesn't *move* it. Savings goals are tracked against real account balances or "earmarked" amounts — no "Add money" button that actually transfers funds. (Plaid Transfer exists but is US-only, heavier compliance; out of scope.) |
| **Plaid secret can't live on the phone** | A small backend is required (token exchange, webhooks, sync). Supabase (Postgres + Edge Functions + Auth) is a good fit and already connected. |
| **Plaid sync isn't instant** | Transactions arrive via webhooks, typically minutes to hours after the card swipe. Pending → posted transitions must be handled. |
| **Up to 4 banks per user** | 4 Plaid *Items*; each Item may expose several accounts (checking, savings, credit card). |

## 2b. Regions & banks

**Primary markets: Europe, United States, Canada.** Anything else is a bonus.

| Region | Plaid coverage | Your banks | Notes |
|---|---|---|---|
| United States | Plaid core market | — | Account type/subtype gives debit vs credit directly |
| Canada | Supported | Your Canadian bank(s) | Debit = Interac (`INTERAC`, `IDP PURCHASE`); `E-TRANSFER` / `Interac e-Transfer` = transfer; CAD |
| France / EU | Supported through Plaid's EU coverage | **La Banque Postale**, **Revolut** (both already used with Plaid) | Labels: `ACHAT CB` / `CB` = card, `PRLV` / `PRELEVEMENT` = direct debit, `VIR` / `VIREMENT` = transfer, `RETRAIT DAB` = ATM, `CHQ` = check. Deferred-debit cards possible (LBP offers them) |
| UK | Supported | — | `DD` = direct debit, `FPS` / Faster Payment = transfer, `SO` = standing order |
| Germany & others | Supported | — | `Kartenzahlung` = card, `Lastschrift` = direct debit, `Überweisung` = transfer |

- **Revolut** exposes one account per currency (EUR, USD, GBP…). Each comes through Plaid as its own account with its own currency, so it shows as several accounts under one bank. Moving money between your own Revolut currency accounts is detected as a transfer, not spending.
- Plaid Link is opened with the user's country codes (`US`, `CA`, `FR`, `GB`, `DE`, `ES`, `IE`, `NL`, …) so the bank search shows the right institutions.
- The label rules are a small table per country, kept in the backend so they can be updated without shipping a new app version.

## 3. Features

Priority legend: **P0** = MVP, **P1** = shortly after, **P2** = later / nice to have.

### 3.1 Accounts & bank linking

| # | Feature | Priority |
|---|---|---|
| A1 | Link up to 4 institutions via Plaid Link (native iOS SDK) | P0 |
| A2 | Show every account under each bank (checking, savings, credit, loans) with live balance | P0 |
| A3 | Include/exclude an account from totals & stats (e.g. ignore a joint account) | P0 |
| A4 | Rename / nickname accounts, pick a color per account | P1 |
| A5 | Re-auth flow when a bank connection breaks (Plaid "update mode"), with a banner on the home screen | P0 |
| A6 | Pull-to-refresh + background refresh; "last synced 3 min ago" indicator | P0 |
| A7 | Net worth = assets − liabilities, across all accounts | P1 |
| A8 | Manual accounts (cash, an account Plaid can't connect) | P2 |

### 3.2 Transactions

| # | Feature | Priority |
|---|---|---|
| T1 | Unified feed across all accounts, grouped by day, with merchant logo + category icon | P0 |
| T2 | Search (merchant, amount, note) and filters (account, category, pocket, date, amount range, income/expense) | P0 |
| T3 | Transaction detail: merchant, map/location if available, account, category, pocket, notes, tags | P0 |
| T4 | Pending vs posted states | P0 |
| T5 | **Transfer detection** — money moving between your own linked accounts is marked as a transfer and excluded from spending (critical with 3–4 banks, otherwise everything is double-counted) | P0 |
| T6 | Credit card payment detection (paying your card from checking ≠ spending) | P0 |
| T7 | Split a transaction across categories (e.g. Costco: groceries + household) | P1 |
| T8 | Exclude a transaction from stats (reimbursed, one-off) | P0 |
| T9 | Attach a receipt photo | P2 |
| T10 | Mark as reimbursable / "owed to me" and track until repaid | P2 |
| T11 | **Payment method tag** on every transaction: Debit card · Credit card · Deferred card · Direct debit · Transfer · ATM · Check | P0 |
| T12 | US/Canada: method from Plaid account type/subtype (checking vs credit card) + payment channel | P0 |
| T13 | France/EU: method parsed from bank labels (`CB`/`CARTE` = card, `PRLV` = direct debit, `VIR` = transfer, `RETRAIT DAB` = ATM, `CHQ` = check), user can correct per account | P0 |
| T14 | **Deferred-debit cards (carte à débit différé)**: purchases count on purchase day; the month-end lump (`FACTURE CARTE`…) is matched to the cycle and tagged *Card settlement* (excluded, like a credit-card payment). Card screen shows "€560 this cycle, debited Nov 30" | P0 |
| T15 | Accounts & cards screen: each card with its type, credit utilization / due date, deferred cycle total | P1 |

### 3.3 Categorization

| # | Feature | Priority |
|---|---|---|
| C1 | Auto-categorize using Plaid's `personal_finance_category`, mapped to *your* categories | P0 |
| C2 | Recategorize with one tap; swipe actions in the feed | P0 |
| C3 | **Rules**: "Always put *Uber* in *Transport*" — offered automatically after you recategorize the same merchant twice | P0 |
| C4 | Custom categories (name, emoji/icon, color) | P0 |
| C5 | **Review inbox**: new uncategorized / low-confidence transactions queue up; triage with swipe cards (Tinder-style) | P1 |
| C6 | Merchant renaming ("SQ *BLUE BOTTLE 0423" → "Blue Bottle") | P1 |

### 3.4 Pockets (category groups) — recommendation

**Your idea is good, and it's a proven pattern** (Buddy, YNAB, Copilot all group categories). I'd frame it as a two-level hierarchy:

```
Pocket            Categories
─────────────     ──────────────────────────────────
🏠 Home           Rent · Utilities · Internet · Insurance
🍔 Food           Groceries · Restaurants · Coffee · Delivery
🚗 Getting around Gas · Uber · Parking · Car payment
🎉 Lifestyle      Shopping · Entertainment · Subscriptions
```

Rules that keep it simple:
- Each category belongs to **exactly one** pocket (no ambiguity in stats).
- Every transaction has a category → its pocket is implied. You never assign a pocket by hand.
- Stats can be viewed at **pocket level** (big picture) and **drilled into** category level.
- Budgets (3.6) can be set on a pocket *or* a category.
- Ship with a sensible default set; fully editable (drag categories between pockets).

| # | Feature | Priority |
|---|---|---|
| P1 | Pockets containing categories, with default set | P0 |
| P2 | Pocket detail: total for period, trend, categories breakdown, transactions | P0 |
| P3 | Drag-and-drop reorganization | P1 |

> Alternative name ideas if "pocket" feels off for a non-savings concept: *Groups*, *Areas*, *Buckets*.

### 3.5 Pay periods & stats

| # | Feature | Priority |
|---|---|---|
| S1 | **Pay period engine**: detect paychecks (recurring income deposits) and suggest a schedule (weekly / bi-weekly / semi-monthly / monthly); user confirms or sets manually | P0 |
| S2 | Global period switcher: **Pay period · Month · Week · Year · Custom** — every stat screen respects it | P0 |
| S3 | Spending total with bar/line/donut views (like Revolut's toggle) | P0 |
| S4 | Breakdown by pocket → category → merchant | P0 |
| S5 | Income vs expenses + **net cash flow** per period | P0 |
| S6 | **Period-over-period comparison** ("$212 more on Food than last pay period") | P0 |
| S7 | **Cumulative spend curve**: this period vs. average period, day by day — shows if you're running hot | P1 |
| S8 | Top merchants, largest transactions, number of transactions | P1 |
| S9 | **Savings rate** per period (% of income not spent) | P1 |
| S10 | Spending heatmap calendar (which days you spend most) | P1 |
| S11 | Day-of-week / time-of-day patterns | P2 |
| S12 | Sankey flow: income → pockets → savings | P2 |
| S13 | Per-account spending split (which card do I actually use) | P1 |
| S14 | Average daily spend & "safe to spend per day" until next paycheck | P0 |

### 3.6 Budgets / spending limits

| # | Feature | Priority |
|---|---|---|
| B1 | Budget (spending limit) per pocket or category, per pay period or per month | **P0** |
| B2 | Progress rings / bars with "on track / at risk / over" states and pace marker | **P0** |
| B3 | Rollover unused budget to next period (optional) | P2 |
| B4 | Push alert at 80% (getting close) and 100% (limit exceeded), once per category per period | **P0** |

### 3.7 Planning & savings goals

| # | Feature | Priority |
|---|---|---|
| G1 | Create a goal: name, emoji/image, target amount, target date | P0 |
| G2 | Goal funding source (pick one): **(a)** linked to a savings account balance, **(b)** earmarked portion of a balance (virtual envelope), or **(c)** manually logged contributions | P0 |
| G3 | Required pace: "Save $185 per pay period to hit this by June" | P0 |
| G4 | On-track / behind projection line chart | P1 |
| G5 | Milestones (25/50/75/100%) with celebration animation + haptics | **P0** |
| G9 | **Push notification when a goal is reached** (and optional milestone pushes) | **P0** |
| G6 | **Plan / forecast**: project end-of-period balance from recurring bills + average spend | P1 |
| G7 | "What if" planner: "If I cut Restaurants by 30%, goal X arrives 2 months earlier" | P2 |
| G8 | Debt payoff goals (credit card / loan balance trending to 0) | P2 |
| G10 | **Shared goals**: invite a partner (iMessage link, they sign in with Apple). Each person counts their own money (earmark / account / manual log); no money moves. Two-color ring, per-person share, activity feed, "cheer" nudge | P1 |
| G11 | Shared-goal privacy: partner always sees goal progress; optionally your amount (else only your %); never your transactions or balances. Leaving splits it back into personal goals | P1 |

### 3.8 Recurring & subscriptions

| # | Feature | Priority |
|---|---|---|
| R1 | Detect recurring charges via Plaid's recurring transactions endpoint | P1 |
| R2 | Upcoming bills calendar for the current pay period ("$1,240 of bills still due before payday") | P1 |
| R3 | Subscription list with monthly/annual total, price-increase detection | P1 |

### 3.9 Insights & notifications

| # | Feature | Priority |
|---|---|---|
| N1 | Payday summary: "Last period you spent $2,340, saved 18%" | P1 |
| N2 | Unusual transaction alerts (much larger than usual for that merchant) | P2 |
| N3 | Weekly digest | P2 |
| N4 | **Widgets**: Home Screen small (safe-to-spend), small (single goal, configurable), medium (pay period + pockets), large (goals); Lock Screen circular / rectangular | **P0** |
| N6 | Alert settings screen: toggle each notification type | **P0** |
| N7 | Bills due tomorrow + bank needs reconnecting alerts | P1 |
| N5 | Ask-your-money chat ("how much did I spend on Uber in October?") using Claude | P2 |

### 3.10 Security & app basics

| # | Feature | Priority |
|---|---|---|
| X1 | **Sign in with Apple — the only login method** (no email/password, no Google) | P0 |
| X2 | Face ID lock on open + privacy blur in app switcher | P0 |
| X3 | Hide balances toggle (tap/shake to reveal) — Revolut-style | P1 |
| X4 | **Display currency setting** (USD / CAD / EUR / GBP / CHF, more later): every amount, chart, budget and goal converts. Balances at today's rate; past transactions at their own date's rate; original amount shown under foreign transactions | **P0** |
| X7 | **Light & dark mode**, following iOS by default, overridable in Settings (System / Light / Dark) | **P0** |
| X8 | **French + English** at launch (String Catalog), locale-aware numbers, dates and currency (`12 480,32 €`, `13 nov.`); app language independent from display currency | **P0** |
| X5 | CSV export | P2 |
| X6 | Delete account & all data, unlink banks | P0 |

## 4. Proposed app structure (high level, for orientation only)

Tab bar (4 tabs + floating action):

1. **Home** — total balance, safe-to-spend, pay-period progress, accounts carousel, recent transactions, alerts
2. **Activity** — transaction feed, search, filters, review inbox
3. **Insights** — stats, charts, pockets, budgets, recurring
4. **Plan** — goals, forecast, what-if

Detailed flows, screens and motion come in the next phase.

## 5. Suggested MVP scope

Everything marked **P0**: Sign in with Apple, linking 4 banks, unified feed with transfer detection, categories + pockets + rules, pay-period engine, core stats (totals, breakdown, comparison, net cash flow, safe-to-spend), budgets/limits, goals with milestones, push notifications (goal reached, limit close/exceeded), widgets, Face ID.

Design canvas (flows, screens, motion): https://claude.ai/artifact/H2gQvgcEXUZLpBW9YVKo94

## 6. Tech direction (to confirm later)

- **iOS**: **Swift + SwiftUI (decided)**, iOS 17+, Swift Charts, SwiftData for local cache, Plaid LinkKit, WidgetKit, APNs push
- **Backend**: Supabase — Postgres + Row Level Security, Edge Functions for Plaid token exchange, `/transactions/sync`, webhooks
- **Animations**: SwiftUI springs, `matchedGeometryEffect`, `contentTransition(.numericText())` for rolling numbers, sensory feedback (haptics)

## 7. Open questions for you

1. **Pockets name** — keep "Pockets" or prefer Groups / Buckets / Areas?
2. **Goals funding** — do you have dedicated savings accounts per goal, or would you rather earmark parts of one balance (G2 b)?
3. **Pay schedule** — what's your pay frequency? Do you have multiple income sources?
4. **Budgets** — do you want spending limits in MVP, or just stats first?
5. **Single user only**, or should a partner be able to share the view later?
6. ~~Currencies~~ — answered: banks in France (La Banque Postale, Revolut) and Canada; target markets Europe + US + Canada.
7. **Plaid account** — do you already have Plaid API keys (Sandbox / Production)?
8. Anything in P1/P2 you want promoted to MVP — or cut?

## Appendix — references reviewed (Mobbin)

- Revolut analytics: [period chart toggle](https://mobbin.com/screens/691ffd53-5aba-4a39-bfa6-6064a299bdcd), [bar view with average](https://mobbin.com/screens/69913e7a-7c90-4051-9fe1-84f2f55920d9), [analytics overview cards](https://mobbin.com/screens/df7b1aab-511c-4959-9238-7ec8da733902), [donut view](https://mobbin.com/screens/56d80261-ebab-49c4-aa2c-de9e23c41abb), [budget allocations](https://mobbin.com/screens/519ee7b9-37d5-41ca-99d9-729905be9547)
- Category groups (pocket concept): [Buddy](https://mobbin.com/screens/73e2ae37-edaf-4464-8bc6-8a49cc4e6cf4), [Copilot](https://mobbin.com/screens/cee0bf4c-54a2-4ce8-8bba-4267b38eea12), [YNAB](https://mobbin.com/screens/51cbfcf5-3cba-4152-b606-a391eae5dbba)
- Goals: [Quicken (goal by account)](https://mobbin.com/screens/01eb82a0-9c38-43ba-b6e7-1c71edc9e252), [Rocket Money (ring + milestones)](https://mobbin.com/screens/64bca473-bfd7-4c47-a7ca-381dc794f917), [Cleo](https://mobbin.com/screens/9cb73cdc-e02f-4ce0-bf26-15c34118428d)
