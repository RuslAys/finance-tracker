# Flutter architecture

Use a small feature-first architecture. Do not introduce Clean Architecture layers, repositories, use-case classes, or state-management dependencies without a demonstrated need.

```text
Flutter screens
   ↓
TrackerController / ChatController
   ↓
Canonical TrackerDocument
   ├── FinanceEngine       # deterministic balances, cash flow, holdings
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
│   │   ├── models/            # Account, Transaction, Trade, TrackerDocument
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
│       ├── chat/
│       └── settings/
└── test/
```

`TrackerStore` is the only storage interface because the product explicitly supports two storage backends. It converts a workbook or Google Sheet through `SchemaMapper` before exposing a canonical `TrackerDocument`.

## State

Start with Flutter's built-in `ChangeNotifier` and `ValueNotifier`.

- `TrackerController` owns the opened tracker, edits, saves, validation errors, and current storage source.
- Feature screens render controller state and call explicit actions.
- `ChatController` owns a conversation's streamed messages and selected data scope.

Add a state-management package only when controller sharing becomes a measured problem.

## Boundaries

- `FinanceEngine` receives canonical models only; it never reads spreadsheet cells.
- `SchemaMapper` is the compatibility boundary for user-customised schemas.
- `SnapshotBuilder` provides scoped, read-only data to the local companion.
- The local companion never parses spreadsheets or reimplements finance calculations.
