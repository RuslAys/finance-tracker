# Finance Tracker

An open-source, local-first finance tracker for mobile and web.

The repository contains the design documentation and the first slices of the Flutter client: the canonical domain model, its validation, the deterministic finance engine, and a read-only Material 3 UI over them. Storage adapters, imports, editing, and the optional companion are not implemented yet.

## AI-generated project

This project is developed with AI assistance. Documentation, code, tests, and pull requests may be AI-generated or AI-modified; a human contributor remains responsible for reviewing every change before it is merged.

## Product direction

- Flutter application for iOS, Android, and web.
- Finance calculations and bank-import validation run in the client.
- A tracker is stored either in a local `.xlsx` workbook or one Google Sheet.
- An optional local companion may later provide ADK analytics and an MCP interface for coding assistants.

## Documentation

- [Architecture](docs/architecture.md)
- [Flutter architecture](docs/flutter-architecture.md)
- [User interface](docs/ui.md)
- [Spreadsheet format](docs/spreadsheet-format.md)
- [Privacy and LLM boundaries](docs/privacy-and-llm.md)
- [Local companion](docs/local-companion.md)

## Status

`app/lib/domain/` holds the canonical model, schema validation, exact decimal arithmetic, the balance, cash-flow, and FIFO holdings calculations, and exact cross-currency conversion with instrument market value. `app/lib/features/` holds `TrackerController` and the dashboard, transactions, and assets screens; until a storage adapter exists the app opens a synthetic sample document. Tests live in `app/test/`; run them with `flutter test` from `app/`.

## License

[MIT](LICENSE)
