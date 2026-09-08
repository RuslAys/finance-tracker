# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

Documentation plus the implemented slices of the Flutter client: `app/lib/domain/` (canonical model, schema validation, exact decimals, finance engine, FX conversion) and `app/lib/features/` (`TrackerController` plus read-only dashboard, transactions, and assets screens), with tests in `app/test/`. `app/pubspec.yaml` is a Flutter package using `flutter_lints`; run `flutter test` and `flutter analyze` from `app/`. `app/lib/storage` is still empty and reserved, so `main.dart` opens the synthetic `features/sample_tracker.dart` document. Adding storage, import, editing, or companion code is an explicit user decision, not a prerequisite for other work.

`AGENTS.md` is the binding repository guidance; read it before changing anything. `CONTRIBUTING.md` holds the AI-agent pull-request rules.

## Architecture

Follow `docs/product.md`: build a client-first financial helper for individuals, with optional family features. Personal tracking and deterministic goals/actions require no household setup; add shared ownership/goals, then one-way consolidation of approved separate sources. Ownership and UI filters are not access controls. Completing an action does not move money or increase goal progress. Monitoring initially runs on refresh or edit in the open app; the companion does not continuously monitor sources.

Client-first, no product-operated backend. The Flutter app owns all finance rules, import validation, and analytics; a tracker's source of truth is either a local `.xlsx` workbook or one Google Sheet — never both, and v1 has no automatic two-way sync. Native mobile cloud BYOK uses a user-provided key held in platform secure storage. The optional local companion (ADK analytics + read-only MCP tools) may hold its own provider credentials and operates on a computed read-only snapshot the app hands it; it never persists or writes tracker data.

Two invariants shape nearly every design decision:

- **Deterministic client code is the authority for money.** An LLM may explain a computed result, propose a schema migration, or summarize a snapshot. It never computes a balance, applies a migration, or writes a transaction. Every LLM-originated change runs through: proposal → compatibility check → user reviews diff → backup → apply → new schema version.
- **Storage maps to the canonical model; external analytics receive only approved snapshots.** Users may use a custom spreadsheet schema, normalized via a `mappings` tab whose `transform` values are a closed set (`identity`, `trim`, `date_iso`, `money_to_minor`, `decimal_string`, `account_alias`, `enum`) parameterized by declarative JSON, never executable code. MCP tools and LLMs receive only a computed, scoped snapshot, never the canonical document, custom columns, raw bank files, or OAuth tokens. Contributors must approve including their data in an AI snapshot; household sharing alone is not that approval.

## Data rules

`docs/spreadsheet-format.md` is the schema of record. Money is integer minor units, fractional quantities are decimal strings — no binary floating point anywhere in a money or holdings path. IDs are UUIDs; row numbers are never identifiers. Dates are `YYYY-MM-DD`. Workbooks carry no macros, formulas, or external links, so the same layout works for `.xlsx` and Google Sheets. Import de-duplication keys on the bank identity `(account_id, source, source_id)`, with `row_fingerprint` checked on every row regardless — a bare `source_id` is not unique across banks or accounts.

Never commit real financial records, bank exports, OAuth tokens, or API keys — including in tests and fixtures. `.gitignore` blocks `data/`, `imports/`, `backups/`, and all `*.env` forms at any depth. It also blocks every `*.xlsx`/`*.xls`/`*.csv`/`*.ofx`/`*.qif` at any depth, except those specific extensions below `app/test/fixtures/`; synthetic import fixtures belong there. A fixture with any other extension, or a fixture anywhere else, is silently unstageable.

## Working here

Favor the smallest client-first change. Keep the README short and put durable design detail in `docs/`, updating the relevant document whenever a documented decision changes. Non-trivial finance, import, security, or migration logic needs one runnable test alongside it.
