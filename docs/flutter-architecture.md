# Flutter architecture

Use a small feature-first architecture. Do not introduce Clean Architecture layers, repositories, use-case classes, or state-management dependencies without a demonstrated need.

The diagrams describe the target layout. Currently the domain model and calculations, `TrackerController`, read-only dashboard, transactions, and assets screens, and the canonical local `.xlsx` reader exist. Portfolios, source mapping, and widget configuration are planned. Implement the [product delivery order](product.md#delivery-order) incrementally; do not scaffold future components.

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

## State

Start with Flutter's built-in `ChangeNotifier` and `ValueNotifier`.

- `TrackerController` owns the opened tracker, edits, saves, validation errors, and current storage source.
- Extend it with the reporting period, freshness/completeness, goals, and accepted actions as those features ship. Add a selected member only for optional family views; personal use must not require member records. Screens reuse computed results; no separate household state framework is needed.
- Feature screens render controller state and call explicit actions.
- Add portfolio selection and per-widget report settings as configuration ships. Keep source mapping profiles separate from presentation preferences; persist the latter per device and tracker, with stable widget instance IDs. A widget's scope is an input to a deterministic report, not a filtered copy of the tracker that loses transfer or settlement relationships.
- `ChatController` owns a conversation's streamed messages and selected data scope.

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

Represent initial portfolios as named groups of accounts, with at most one portfolio per account. Reuse the existing FIFO books and price/FX calculations. Compute the All portfolios report from unique included account IDs, including unassigned investment accounts; never aggregate independently configured widget totals. Validate the complete record relationships before applying report scope, and retain context for movements crossing that scope.

Each widget type declares the canonical data and report options it needs. Validate those requirements before requesting its report. An unavailable entity does not become an empty list or zero amount; report eligibility follows available, valid data. Keep parsing errors separate from financial validation and report-level missing prices/rates so the UI can explain the affected feature. The current reader/controller do not yet implement this availability model.

Use small typed settings and existing Flutter state primitives. Source mappings select and normalize records; widget settings choose scope and presentation. Neither executes user code. Do not introduce per-widget spreadsheet parsers, a plugin runtime, or a new state-management dependency for configuration.

## Boundaries

- `FinanceEngine` receives canonical models only; it never reads spreadsheet cells.
- Reports use explicit date and currency policies. Filter historical cash and trades to the valuation date, and gate affected suggestions on data quality; see [reporting prerequisites](product.md#monitoring-and-reporting-prerequisites).
- Goal allocations cannot exceed available funds or allocate the same money twice. Marking an action done changes action state only.
- Later consolidation normalizes and reconciles approved sources in Flutter before calculation. Retain provenance outside bank identity fields and do not mutate source trackers.
- `SchemaMapper` is the compatibility boundary for user-customised schemas.
- `SnapshotBuilder` provides scoped, read-only data to the local companion.
- The local companion never parses spreadsheets or reimplements finance calculations.
