# Flutter architecture

Use a small feature-first architecture. Do not introduce Clean Architecture layers, repositories, use-case classes, or state-management dependencies without a demonstrated need.

The diagrams describe the target layout. Currently the domain model and calculations, `TrackerController`, read-only dashboard, transactions, and assets screens, the canonical local `.xlsx` reader, and read-only portfolio grouping and reports exist. Portfolio editing, source mapping, and widget configuration are planned. Implement the [product delivery order](product.md#delivery-order) incrementally; do not scaffold future components.

```text
Flutter screens
   ↓
TrackerController / ChatController
   ↓
Canonical TrackerDocument
   ├── FinanceEngine       # deterministic reports, goal progress, suggestions
   ├── SchemaMapper        # custom workbook or Sheet → canonical fields
   ├── TrackerStore        # XLSX or Google Sheets read/write
   └── SnapshotBuilder     # scoped, read-only data for local AI companion
```

## Layout

```text
app/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── domain/
│   │   ├── models.dart        # Account, Transaction, Trade, TrackerDocument
│   │   ├── finance.dart       # deterministic calculations
│   │   ├── schema.dart        # canonical schema and validation
│   │   └── snapshot.dart      # LLM/MCP-safe finance snapshot
│   ├── storage/
│   │   ├── xlsx_store.dart    # implemented: read-only local XLSX
│   │   ├── xlsx_parts.dart    # implemented: SpreadsheetML cell reader
│   │   ├── tracker_store.dart # local XLSX and Google Sheets contract
│   │   ├── google_sheets_store.dart
│   │   └── mapping.dart       # custom mappings and migrations
│   └── features/
│       ├── dashboard/
│       ├── transactions/
│       ├── imports/
│       ├── assets/
│       ├── goals/             # planned goals and accepted actions
│       ├── chat/
│       └── settings/
└── test/
```

`TrackerStore` is the only storage interface because the product explicitly supports two storage backends. It converts a workbook or Google Sheet through `SchemaMapper` before exposing a canonical `TrackerDocument`. Only `xlsx_store.dart` exists so far: it reads the canonical tabs of a local workbook and throws with every problem found rather than opening a partly understood file. One reader needs no interface; add `TrackerStore` when a second backend or a writer arrives.

## Large workbooks

The following is the recommended performance work, of which only the worksheet reader is implemented. It belongs to the existing storage and reporting work; it does not change the product delivery order or add workbook writing.

The opener no longer parses a whole worksheet or the shared-string table into a document tree: `xlsx_parts.dart` pulls those parts event by event and builds a tree for one `<row>` or `<si>` at a time, drops each decompressed part once read, and `openWorkbookFile` reads the container from a file stream rather than from the whole compressed file in memory. It still retains a cell grid for every worksheet and builds row maps before creating the canonical document, so peak memory remains larger than the compressed file. Loading and initial calculations finish before `runApp`, and the controller retains the whole document afterward. The transactions list builds widgets lazily, but its backing data remains in memory.

Prioritize these changes:

1. Remove eager collections of row maps and release intermediate cells as soon as their values are consumed. Avoid retaining unused worksheet data while preserving container and canonical-field validation.
2. Done for worksheets and shared strings, using the existing `xml` dependency's [event-based API](https://pub.dev/packages/xml); small metadata parts keep DOM parsing. The events are still pulled from one decoded part string, so input memory is bounded by the largest part rather than by a row. Shared strings remain an in-memory indexed list; consider incremental decoding or disk-backed lookup only if measurements justify it.
3. Enforce resource limits on compressed input, actual decompressed bytes, archive entries, text lengths, and parsing work. A cell reference past the last column of a sheet is already refused rather than padded into an unbounded row, and a part that stops mid-sheet is refused rather than read as the rows that arrived. Do not trust ZIP size declarations alone. Exceeding a limit must reject the load explicitly, never truncate financial records into an apparently valid tracker. If diagnostics are capped, state that further errors were omitted.
4. Display loading progress and cancellation before parsing. On mobile and desktop, move parsing and expensive calculations to a background isolate, avoiding unnecessary copies of workbook bytes and results. An isolate improves responsiveness but does not remove the dataset's memory cost.
5. Reuse document validation, transaction ordering, and calculated holdings when their inputs have not changed. Month or portfolio selection should recompute only affected results. Index price/FX history when repeated scans become expensive, retaining the selected provider and as-of date policies.

Platform adapters remain necessary:

| Platform | Loading and execution |
| --- | --- |
| Web | Browser workbook opening is not implemented by the current `dart:io.File` path. Add browser file selection and a browser-compatible input adapter. Use a Web Worker for CPU work; Flutter `compute()` runs on the main thread on web. |
| Mobile | Add document-provider access and handle platform sandbox permissions; copy to app-local storage only when needed. Test memory pressure, cancellation, and lifecycle interruptions on representative phones. |
| Desktop | File-backed input is in place, so the full compressed file is no longer retained. Background work and resource limits still matter even when more RAM is available. |

See [Flutter's isolate limitations](https://docs.flutter.dev/perf/isolates). Benchmark synthetic workbooks with varied row counts, text lengths, shared versus inline strings, sparse columns, price/FX histories, and invalid input. Measure peak process memory, retained heap after loading, time to usable reports, and interaction latency separately. Native Dart parser measurements do not establish mobile or browser limits. Keep runnable regression checks for exact parsing and financial relationships when changing the loader.

## Conditional SQLite cache

This section concerns workbook caching. [Saved chat](chat-and-skills.md#conversation-storage) separately justifies disk-backed storage when that feature ships; its history is not rebuildable from a tracker.

Do not add an in-memory database to reduce RAM: SQLite [`:memory:`](https://www.sqlite.org/inmemorydb.html) retains its database in memory, and indexes plus Dart query results can add further copies. First measure the streaming reader and reporting improvements above.

Introduce disk-backed SQLite only if retained data size, repeated queries, or reopening time still exceeds the target devices' budgets. Its benefit requires paged UI queries and bounded or ordered report inputs; rebuilding the complete `TrackerDocument` from SQLite would retain the main memory cost. Such a change must preserve full transfer/settlement validation and FIFO history before report scoping. Finance rules stay in Flutter, with exact integer minor units and decimal quantities/rates; do not move them into floating-point SQL expressions.

If a database becomes necessary, prefer a shared SQLite schema and query implementation across native and web rather than unrelated database models. Evaluate a maintained Flutter integration such as [Drift](https://drift.simonbinder.eu/platforms/web/) then; no database dependency is selected now. Native uses filesystem storage, while web needs SQLite WASM, workers, and browser storage such as OPFS. Browser quotas, cleared site data, private-mode fallbacks, and multi-tab locking remain platform concerns. Do not silently fall back to an in-memory database for a workbook that exceeds the memory budget. Some configurations require COOP/COEP headers that affect Google authentication popups; test the database and OAuth flow together.

SQLite used for workbook caching is a rebuildable, app-local cache, never a third tracker source or an automatic synchronization mechanism. Identify cached data by source identity and content/version plus schema and mapping versions, not just a path or tracker ID. Activate a replacement only after loading and validation succeed. A failed refresh leaves any retained results explicitly stale or unavailable, never an empty or current-looking tracker. Browser cache loss requires reopening the source. The optional companion neither builds nor owns this cache.

A persistent cache creates another copy of financial data. Keep it in app-private storage, provide deletion, define retention and backup behavior, and do not treat ordinary SQLite as encrypted storage. Credentials belong in the separate [credential stores](privacy-and-llm.md#credentials), never in cached tracker tables.

## State

Start with Flutter's built-in `ChangeNotifier` and `ValueNotifier`.

- `TrackerController` owns the opened tracker, edits, saves, validation errors, and current storage source.
- Extend it with the reporting period, freshness/completeness, goals, and accepted actions as those features ship. Add a selected member only for optional family views; personal use must not require member records. Screens reuse computed results; no separate household state framework is needed.
- Feature screens render controller state and call explicit actions.
- Add portfolio selection and per-widget report settings as configuration ships. Keep source mapping profiles separate from presentation preferences; persist the latter per device and tracker, with stable widget instance IDs. A widget's scope is an input to a deterministic report, not a filtered copy of the tracker that loses transfer or settlement relationships.
- `ChatController` owns the active conversation's bounded message window, streaming answer, and selected data scope. Persist saved history separately and budget model context according to the [chat and skills design](chat-and-skills.md).

Add a state-management package only when controller sharing becomes a measured problem.

## Portfolio and configuration flow

The planned flow reuses the canonical model and finance engine:

```text
Workbook cells + selected source mapping profile
                    ↓ normalize and validate
Canonical TrackerDocument + entity availability and source diagnostics
                    ↓ FinanceEngine + requested report scope
Calculated reports + completeness and valuation metadata
                    ↓ widget instance settings
Dashboard, Transactions, Assets, and future feature widgets
```

Implement mapping at the storage boundary, shared by every feature. Reuse `xlsx_parts.dart` for cell decoding and the canonical field parsers and validation rules; keep source locations for errors. A canonical workbook needs no custom profile. Mapping configuration is declarative, using only supported transforms from the [spreadsheet contract](spreadsheet-format.md#custom-schemas-and-mappings).

Portfolios are named groups of accounts, with at most one portfolio per account. `FinanceEngine.portfolioGroups` builds them and `FinanceEngine.portfolioReport` values a set of account IDs, reusing the existing FIFO books and price/FX calculations. The All portfolios report is computed from the unique included account IDs, including unassigned investment accounts; independently configured widget totals are never aggregated. Validate the complete record relationships before applying report scope, and retain context for movements crossing that scope.

Each widget type declares the canonical data and report options it needs. Validate those requirements before requesting its report. An unavailable entity does not become an empty list or zero amount; report eligibility follows available, valid data. Keep parsing errors separate from financial validation and report-level missing prices/rates so the UI can explain the affected feature. `portfolioReport` does this for investments: it names each cause, and withholds its totals when a record of the included accounts fails validation. The rest of the reader/controller does not yet implement this availability model.

Use small typed settings and existing Flutter state primitives. Source mappings select and normalize records; widget settings choose scope and presentation. Neither executes user code. Do not introduce per-widget spreadsheet parsers, a plugin runtime, or a new state-management dependency for configuration.

## Boundaries

- `FinanceEngine` receives canonical models only; it never reads spreadsheet cells.
- Reports use explicit date and currency policies. Filter historical cash and trades to the valuation date, and gate affected suggestions on data quality; see [reporting prerequisites](product.md#monitoring-and-reporting-prerequisites).
- Goal allocations cannot exceed available funds or allocate the same money twice. Marking an action done changes action state only.
- Later consolidation normalizes and reconciles approved sources in Flutter before calculation. Retain provenance outside bank identity fields and do not mutate source trackers.
- `SchemaMapper` is the compatibility boundary for user-customised schemas.
- `SnapshotBuilder` provides scoped, read-only data to the local companion.
- The local companion never parses spreadsheets or reimplements finance calculations.
