# Flutter architecture

Use a small feature-first architecture. Do not introduce Clean Architecture layers, repositories, use-case classes, or state-management dependencies without a demonstrated need.

The diagrams describe the target layout. Currently only the domain model and calculations, `TrackerController`, and read-only dashboard, transactions, and assets screens exist. Implement the [product delivery order](product.md#delivery-order) incrementally; do not scaffold future components.

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
│   │   ├── tracker_store.dart # local XLSX and Google Sheets contract
│   │   ├── workbook_store.dart
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

`TrackerStore` is the only storage interface because the product explicitly supports two storage backends. It converts a workbook or Google Sheet through `SchemaMapper` before exposing a canonical `TrackerDocument`.

## State

Start with Flutter's built-in `ChangeNotifier` and `ValueNotifier`.

- `TrackerController` owns the opened tracker, edits, saves, validation errors, and current storage source.
- Extend it with the reporting period, freshness/completeness, goals, and accepted actions as those features ship. Add a selected member only for optional family views; personal use must not require member records. Screens reuse computed results; no separate household state framework is needed.
- Feature screens render controller state and call explicit actions.
- `ChatController` owns a conversation's streamed messages and selected data scope.

Add a state-management package only when controller sharing becomes a measured problem.

## Boundaries

- `FinanceEngine` receives canonical models only; it never reads spreadsheet cells.
- Reports use explicit date and currency policies. Filter historical cash and trades to the valuation date, and gate affected suggestions on data quality; see [reporting prerequisites](product.md#monitoring-and-reporting-prerequisites).
- Goal allocations cannot exceed available funds or allocate the same money twice. Marking an action done changes action state only.
- Later consolidation normalizes and reconciles approved sources in Flutter before calculation. Retain provenance outside bank identity fields and do not mutate source trackers.
- `SchemaMapper` is the compatibility boundary for user-customised schemas.
- `SnapshotBuilder` provides scoped, read-only data to the local companion.
- The local companion never parses spreadsheets or reimplements finance calculations.
