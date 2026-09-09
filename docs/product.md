# Client-first financial helper

## Product promise

Understand your finances, plan goals, and know what to do next. Keep your data in your own workbook or Google Sheet. Optional family features help you manage shared accounts and goals together.

Client-first means Flutter owns finance calculations, validation, and practical budgeting suggestions, whether storage is local or in Google Sheets. Optional AI explains those results and discusses alternatives. Personal and household reports, goals, and actions must work without an LLM or a product-operated backend.

## Current state

Implemented: the canonical finance model, validation, exact arithmetic, balances, monthly cash flow in one reporting currency, FIFO holdings, currency conversion, historical valuation through an as-of date, a read-only UI, a read-only local `.xlsx` reader, and read-only named investment portfolios with their combined summary. Editing portfolio membership, configurable widgets, custom source mappings, workbook writing, Google Sheets, editing, bank imports, household membership, goals, actions, monitoring, consolidation, and AI integrations are planned, not implemented.

## Investment portfolios

Users can organize investments into named portfolios and inspect both an individual portfolio and a summary of all portfolios within the open tracker. This works for personal use without household setup, an LLM, or separate-source consolidation.

- The initial design groups investment accounts under a portfolio with a stable ID and name. A portfolio can contain several accounts; an account belongs to at most one portfolio. Existing trackers require no portfolio setup, and unassigned investment accounts remain visible in an explicit Unassigned group.
- Each portfolio reports holdings, market value, remaining FIFO cost, realized gains, and unrealized gains. Show account cash separately and label any total that includes both cash and positions. Preserve the account-level FIFO books when grouping holdings for display.
- All portfolios includes named portfolios and unassigned investment accounts, counting each account and position once. It is an investment summary; the existing net-worth report still includes all tracker accounts. Never build totals by adding widget values, which can overlap.
- Combined valuations use one reporting currency, valuation date, and price/FX provider policy. Preserve original amounts and currencies. Define and label the historical conversion policy before aggregating cost and realized gains across currencies; valuation-date FX alone does not establish historical investment performance.
- Missing prices, rates, invalid records, incomplete settlements, or unknown source coverage make affected reports unavailable or explicitly incomplete. Affected means connected to the selected accounts: a half-recorded movement, an impossible sell, or a balance beyond exact arithmetic in one portfolio does not withhold another, but a transfer crossing the selection does. Each portfolio's balances and cost basis are computed from its own accounts' rows. Show data-through dates and stale observations; unknown values are never zero. Keep transfer and settlement validation intact when selecting accounts.

Splitting a single brokerage account into strategy portfolios is deferred pending explicit position/lot allocation, sale attribution, and unallocated-cash rules. Account membership is a reporting grouping, not ownership, access control, or a movement of money.

## Configurable spreadsheets and widgets

Users can keep their own spreadsheet layout and configure every feature widget through the UI. Use two separate configurations: a source mapping converts spreadsheet data into canonical records; widget settings select and present calculated reports. One mapping feeds all applicable widgets, so changing a header mapping cannot give different widgets different interpretations of the same amount.

- Source profiles select sheets/tables, header rows or ranges, columns, supported date and decimal formats, and account/instrument aliases. Provide a preview of normalized records and actionable errors before activating a profile. The canonical layout works without custom setup.
- Each feature exposes relevant widget settings: visibility, order, title, portfolio/account scope, visible fields, sorting, supported grouping, and reporting period. Allow multiple instances of a widget with different scopes and a way to restore defaults. Settings do not override financial validation or conceal warnings attached to visible results.
- A missing or unmapped entity is distinct from a successfully mapped empty table. Enable only reports whose required data is available and valid; explain missing dependencies. A quantity/value snapshot cannot establish FIFO cost or realized gains, and support for such snapshots requires an explicit model extension rather than invented trades or settlements.
- Persist source profiles separately from device-specific presentation preferences. Portable mapping storage and its versioning follow the [spreadsheet contract](spreadsheet-format.md#custom-schemas-and-mappings); a local profile file can support UI configuration before workbook writing exists. Saving a local profile does not modify the source workbook.

Custom layouts remain subject to stable identifiers, exact money conversion, and the no-formulas/no-scripts rules. Arbitrary executable transformations and custom widget code are outside this feature. See the [UI requirements](ui.md#widget-configuration) and [Flutter configuration flow](flutter-architecture.md#portfolio-and-configuration-flow).

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

- Cash flow reports one selected month in the tracker's base currency. Each transaction in another currency is converted with the selected FX provider's rate on that transaction's booking date, then summed in exact minor units. A row without a rate on its date makes the month's totals unavailable and its currency is named on screen; it is never dropped from a total presented as complete.
- Net worth values one date: transactions and trades booked after `asOf` are excluded, and prices and FX rates resolve on or before it. Account balances and the transactions list use the same date, so a listed row and the balance beside it always agree. A movement recorded in more than one row — a trade and its settlement, or the two legs of a transfer — may carry different dates. A valuation between them would count a position and the cash that bought it at once, or lose money in transit between two accounts; it is unavailable on such a date rather than wrong by the amount moved.
- Still open: a data-through date, stale-observation and missing-source reporting, and per-report freshness requirements. Nothing recorded today states how far a user's own entry has got, so no screen may claim complete coverage through the refresh time. Never replace an unknown amount with zero or generate an affected recommendation from it.
- Add recorded upcoming commitments before showing available-to-spend forecasts. A current balance alone does not establish what an individual or household can afford.

## Delivery order

1. Correct reporting periods, currency coverage, historical calculations, and data-quality handling, with runnable regression tests. Periods, booking-date conversion, and as-of filtering are done; data-through and staleness reporting remain.
2. Implement one storage adapter and editing for personal use, with verified writes and recovery. Reading a local `.xlsx` tracker is done; writing, backup, and recovery are not, and no screen edits anything yet.
3. Add investment portfolios and their combined summary over the canonical format; then custom source mapping with preview and saved profiles; then configuration controls across Dashboard, Transactions, and Assets. Reporting prerequisites apply to each slice. Reading portfolios and reporting them individually and combined is done; naming portfolios and assigning accounts from the app waits on verified writes and recovery. Local configuration need not wait for workbook writing.
4. Add personal savings goals, validated allocations, and explainable actions; then add bank imports and commitments to reduce manual upkeep. New feature widgets follow the same configuration requirements.
5. Add optional household members, account ownership, shared goals/actions, and Household/Mine/Joint views. Use one shared Google Sheet for the family pilot; verify concurrent-edit behavior before enabling shared editing.
6. Add one-way consolidation when private or separate sources are needed, extending the local workbook adapter as required.
7. Add optional AI explanations after the helper is useful without them.

Update the versioned schema when implementing portfolio membership, ownership, allocation, import, or consolidation behavior. Add runnable checks for portfolio aggregation without double counting, missing-data handling, exact mapping conversions, and persisted widget scopes as those features ship. Do not scaffold the later phases in advance.
