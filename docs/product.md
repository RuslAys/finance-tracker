# Client-first financial helper

## Product promise

Understand your finances, plan goals, and know what to do next. Keep your data in your own workbook or Google Sheet. Optional family features help you manage shared accounts and goals together.

Client-first means Flutter owns finance calculations, validation, and practical budgeting suggestions, whether storage is local or in Google Sheets. Optional AI explains those results and discusses alternatives. Personal and household reports, goals, and actions must work without an LLM or a product-operated backend.

## Current state

Implemented: the canonical finance model, validation, exact arithmetic, balances, cash flow, FIFO holdings, currency conversion, and a read-only UI over synthetic data. Storage, editing, bank imports, household membership, goals, actions, monitoring, consolidation, and AI integrations are planned, not implemented.

## Personal tracking with optional family features

Start with one personal tracker for accounts, reports, goals, and actions. Individual use requires no household, member setup, or sharing. Its source of truth is either one local `.xlsx` workbook or one Google Sheet.

When family features are needed, add members and ownership to the tracker to include personal and joint accounts and shared goals. Start family support with one shared tracker before implementing consolidation. A shared Google Sheet is the first family pilot target; a local workbook supports an individual or household managed on one device. A local file alone does not provide collaboration between devices.

- A member has a stable ID and display name. Membership is attribution, not a new login or authorization system.
- With family features enabled, an account belongs to one or several members. Several owners do not multiply its balance in household totals.
- Household includes all accounts in the tracker; Mine includes accounts owned by the selected member, including joint accounts; Joint includes accounts with several owners. These views overlap and must not be added together.
- Account ownership does not assign responsibility for each expense. Expense splitting and reimbursements are deferred until explicitly implemented.
- Everyone with access to the shared file can access its included records. Private records belong in separate files; see [privacy boundaries](privacy-and-llm.md#household-sharing).

## Separate trackers and consolidation later

When members need private records or already maintain separate trackers, Flutter may read approved contributions and compute a household view. Each source remains authoritative for its records. A combined workbook or Google Sheet is an optional regenerated report; it is not an independently editable master tracker. Goals and accepted actions stay in the selected household tracker and are not overwritten by report refreshes.

```text
Approved personal and joint sources
                 ↓ explicit refresh in Flutter
Normalize → reconcile → validate → calculate household view
                                      ↓ optional export
                          Local workbook or Google Sheet report
```

Consolidation is one-way, with no writes back to sources and no automatic two-way synchronization. Do not use spreadsheet formulas or external links to combine sources.

- Preserve source tracker and entity IDs separately from bank import identity. Detect copies of the same tracker and reconcile conflicting copies rather than counting both.
- Map accounts explicitly. A joint bank account present in several sources counts once; resolve overlapping or conflicting records before including them. Never deduplicate solely by an equal date and amount.
- Replace each source's prior contribution on a successful refresh so corrections and deletions propagate. A failed refresh is not an empty source: mark retained data stale and the report incomplete.
- Reconcile transfers between included accounts so they do not inflate household income or expense. The current schema requires both same-currency transfer legs in one document; consolidation needs an explicit mapping and reconciliation design before implementation. Do not invent missing legs or silently extend support to cross-currency transfers.
- Normalize categories and use one household reporting currency and a consistent price/rate policy. Preserve original amounts and currencies.
- Show the scope, data-through date, refresh time, and completeness of each contribution. Do not present partial coverage as a complete household total.
- A member may share selected records or summaries. Summaries cannot support transaction-level explanations or transfer reconciliation; do not combine overlapping summary and transaction coverage. Withhold reports that require unavailable detail.

## Goals and actions

Start with personal savings goals: stable ID, name, target amount and currency, and target date. Family features add shared goals and a responsible member; personal goals require no member record. Track progress from explicit allocations of recorded funds. Validate allocations against available funds and prevent the same money from being allocated to several goals. Allocations reserve money for reporting; they do not move money or increase net worth.

Calculate the remaining target and required contribution in exact minor units using an explicit contribution schedule. Show the number of contributions and rounding policy; handle achieved goals and passed deadlines explicitly. Do not treat a target contribution as affordable without sufficient cash-flow and commitment data.

Suggestions start with deterministic rules: review a spending increase, refresh stale data, or adjust the contribution or deadline for a user-selected goal. Show the evidence, reporting period, assumptions, and expected effect. Withhold affected suggestions when inputs are invalid, stale, or incomplete.

Synthetic example: a holiday goal has €1,200 remaining and six monthly contributions left. The required contribution is €200 per month. Against a planned €150 contribution, show the €50 gap and options to change the plan or deadline.

An accepted action has a description, due date, optional goal link, and status (`planned`, `done`, or `dismissed`). Family features add a responsible member; personal actions require no member record. Marking it done does not create a transaction or increase goal progress. Recompute progress from recorded funds and allocations. Repeated refreshes should update an existing suggestion rather than duplicate it; respect dismissals while its supporting facts remain unchanged.

Guidance covers budgeting and user-chosen goals. It does not execute payments or trades or present investment, tax, or legal recommendations as professional advice. AI explanations follow the [LLM boundaries](privacy-and-llm.md#llm-analytics).

## Monitoring and reporting prerequisites

Initially, monitoring means recalculating after an explicit refresh or edit while the app is open. Show both when data was refreshed and the date through which records are complete; a recent refresh does not establish current financial coverage. Reminders to update data must not claim that new bank activity was detected.

Continuous monitoring while the app is closed requires a separately designed execution path. The optional companion does not fetch source records, import transactions, or keep tracker data after the approved snapshot expires.

Before goals or suggestions rely on reporting:

- Add explicit periods and currency coverage. The current controller requests all-time cash flow in the base currency and excludes other currencies rather than converting them.
- For monthly cash flow, convert each included transaction using its booking date and the selected FX provider, then sum exact minor units. Show the policy; a missing rate makes the combined total unavailable.
- For historical net worth, filter transactions and trades through the valuation date as well as selecting prices and FX rates through that date. Currently `asOf` limits quotes and rates only.
- Surface invalid records, missing sources, stale observations, and missing prices/rates. Never replace an unknown amount with zero or generate an affected recommendation from it. Define and display freshness requirements for each report when implementing it.
- Add recorded upcoming commitments before showing available-to-spend forecasts. A current balance alone does not establish what an individual or household can afford.

## Delivery order

1. Correct reporting periods, currency coverage, historical calculations, and data-quality handling, with runnable regression tests.
2. Implement one storage adapter and editing for personal use, with verified writes and recovery.
3. Add personal savings goals, validated allocations, and explainable actions; then add bank imports and commitments to reduce manual upkeep.
4. Add optional household members, account ownership, shared goals/actions, and Household/Mine/Joint views. Use one shared Google Sheet for the family pilot; verify concurrent-edit behavior before enabling shared editing.
5. Add the local workbook adapter and one-way consolidation when private or separate sources are needed.
6. Add optional AI explanations after the helper is useful without them.

Update the versioned schema and add runnable checks when implementing ownership, allocation, import, or consolidation behavior. Do not scaffold the later phases in advance.
