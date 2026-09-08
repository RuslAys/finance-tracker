# Repository guidance

## Current scope

Implemented: the Flutter client's canonical domain layer in `app/lib/domain/`, a read-only Material 3 UI over it in `app/lib/features/`, and their tests. The UI opens a synthetic sample document because no storage adapter exists yet. Do not add storage, import, ADK, MCP, or API implementation unless the user explicitly requests it.

All changes are AI-generated or AI-assisted unless a human author states otherwise. Do not represent generated output as independently human-authored.

## Product constraints

- Follow [product rules and delivery order](docs/product.md): a client-first financial helper for individuals, with optional family features. Personal tracking, goals, and explainable budgeting actions must not require household setup; add shared accounts/goals and one-way consolidation of approved separate sources incrementally.
- The Flutter client owns finance calculations, validation, and bank-import handling.
- Household ownership is attribution, not access control. Keep private records outside shared files.
- Goals and actions must work without an LLM. Completing an action never moves money or increases goal progress; withhold affected suggestions when data is invalid, stale, or incomplete.
- A tracker is stored in either a local `.xlsx` workbook or a Google Sheet; do not introduce automatic two-way synchronization.
- Keep the spreadsheet schema in [docs/spreadsheet-format.md](docs/spreadsheet-format.md) portable: no macros, formulas, external links, floating-point money, or row-number identifiers.
- The optional local companion is not a hosted backend and never owns the tracker data.
- Never use real financial records, bank exports, OAuth tokens, or API keys in the repository.

## Documentation

Keep the README short. Put durable design details in `docs/`; update the relevant document when changing a documented decision.

## Implementation, when requested

Favor the smallest client-first change. Keep external LLM access optional and narrow; never put provider API keys in Flutter builds. Add one runnable test for non-trivial finance or import behavior.

## Pull requests

Follow the AI-agent pull-request rules in [CONTRIBUTING.md](CONTRIBUTING.md). Before proposing a pull request, verify that the diff is scoped, contains no secrets or real financial data, and documents AI assistance and human review.
