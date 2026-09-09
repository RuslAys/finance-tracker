# Finance Tracker

An open-source, client-first financial helper for mobile and web: understand your finances, plan goals, and choose practical next steps using spreadsheets you control. Optional family features support shared accounts and goals.

Implemented: the Flutter finance domain, validation, deterministic calculations, a read-only local `.xlsx` reader, and a read-only Material 3 UI. Portfolios, configurable widgets, custom spreadsheet mappings, writing/editing, imports, household features, goals, monitoring, and AI integrations are planned.

## AI-generated project

This project is developed with AI assistance. Documentation, code, tests, and pull requests may be AI-generated or AI-modified; a human contributor remains responsible for reviewing every change before it is merged.

## Product direction

- Start with one personal tracker in a local `.xlsx` workbook or one Google Sheet; add household members and shared goals when needed.
- Keep calculations, bank-import validation, and goal-based budgeting guidance in Flutter.
- Organize investments into portfolios with a combined summary; configure spreadsheet mappings and feature widgets independently.
- Add one-way consolidation of approved separate sources later; no automatic two-way sync.
- Keep AI explanations optional; goals and actions must work without an LLM.

## Documentation

- [Product rules and delivery order](docs/product.md)
- [Architecture](docs/architecture.md)
- [Flutter architecture](docs/flutter-architecture.md)
- [User interface](docs/ui.md)
- [Spreadsheet format](docs/spreadsheet-format.md)
- [Privacy and LLM boundaries](docs/privacy-and-llm.md)
- [Local companion](docs/local-companion.md)

## Status

`app/lib/domain/` holds the canonical model, schema validation, exact decimal arithmetic, the balance, cash-flow, and FIFO holdings calculations, and exact cross-currency conversion with instrument market value. `app/lib/features/` holds `TrackerController` and the dashboard, transactions, and assets screens. `app/lib/storage/xlsx_store.dart` reads a canonical `.xlsx` tracker; run with `flutter run --dart-define=tracker=<path>` to open one, or without it for a synthetic sample document. Add `--dart-define=price_provider=<name>` and `--dart-define=rate_provider=<name>` when the workbook holds observations from more than one provider; reports never mix them. Nothing writes to a workbook yet. Tests live in `app/test/`; run them with `flutter test` from `app/`.

## License

[MIT](LICENSE)
