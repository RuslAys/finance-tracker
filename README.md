# Finance Tracker

An open-source, client-first financial helper for mobile, desktop, and web: understand your finances, plan goals, and choose practical next steps using spreadsheets you control — a local `.xlsx` workbook or a cloud spreadsheet. Optional family features support shared accounts and goals.

Implemented: the Flutter finance domain, validation, deterministic calculations, a read-only local `.xlsx` reader, opening a workbook the user picks, read-only investment portfolios, and a read-only Material 3 UI. Portfolio editing, configurable widgets, custom spreadsheet mappings, writing/editing, imports, household features, goals, monitoring, and AI integrations are planned.

## AI-generated project

This project is developed with AI assistance. Documentation, code, tests, and pull requests may be AI-generated or AI-modified; a human contributor remains responsible for reviewing every change before it is merged.

## Product direction

- Start with one personal tracker in a local `.xlsx` workbook or one cloud spreadsheet (Google Sheets first; Excel over OneDrive/SharePoint planned); add household members and shared goals when needed.
- Keep calculations, bank-import validation, and goal-based budgeting guidance in Flutter; every write is journaled, backed up, and verified.
- Organize investments into portfolios with a combined summary; configure spreadsheet mappings and feature widgets independently.
- Fetch quotes from BYOK market-data providers with keyless defaults; refresh is always explicit.
- Add one-way consolidation of approved separate sources later; no automatic two-way sync.
- Keep the AI agent optional and BYOK across model providers; it proposes, the deterministic core validates and writes, and goals and actions work without an LLM.

## Documentation

- [Product rules and delivery order](docs/product.md)
- [Architecture](docs/architecture.md)
- [Flutter architecture](docs/flutter-architecture.md)
- [User interface](docs/ui.md)
- [Spreadsheet format](docs/spreadsheet-format.md)
- [Privacy and LLM boundaries](docs/privacy-and-llm.md)
- [Local companion](docs/local-companion.md) (superseded by the in-app provider abstraction)

## Status

`app/lib/domain/` holds the canonical model, schema validation, exact decimal arithmetic, the balance, cash-flow, and FIFO holdings calculations, and exact cross-currency conversion with instrument market value. `app/lib/features/` holds `TrackerController` and the dashboard, transactions, and assets screens. `app/lib/storage/xlsx_store.dart` reads a canonical `.xlsx` tracker, under the resource limits in `WorkbookLimits`; open one from the app's Open workbook action, or start with `flutter run --dart-define=tracker=<path>` to open it immediately, or without either for a synthetic sample document. Add `--dart-define=price_provider=<name>` and `--dart-define=rate_provider=<name>` when the workbook holds observations from more than one provider; reports never mix them. Nothing writes to a workbook yet.

`app/` holds `lib/` and `test/` only. Run `flutter test` and `flutter analyze` from `app/` as it stands; running the app needs `flutter create .` there first, to generate the platform runner directories this repository does not carry.

## License

[MIT](LICENSE)
