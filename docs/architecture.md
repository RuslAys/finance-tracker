# Architecture

## Goal

The client-first financial helper supports individual use with optional family features. Flutter owns finance rules, import validation, personal and household reports, goal progress, and deterministic budgeting suggestions. User data is not stored in a product-operated database. See [product rules and delivery order](product.md).

The finance domain, read-only UI, canonical local `.xlsx` reader, and read-only named portfolios are implemented. Verified writes, cloud providers, the domain tool layer, imports, the agent, market data, the user profile, and the config bundle below are planned work in the [delivery order](product.md#delivery-order).

## Components

```text
Flutter application
├── domain: validation, balances, cash flow, holdings, goals, suggestions
├── tools: typed LLM-independent read / proposal / analytics API over the domain
├── storage: SpreadsheetStore / DirectoryStore adapters with declared capabilities
│   ├── local directory with .xlsx workbook (desktop and mobile)
│   └── cloud providers: Google Sheets/Drive first, Microsoft Graph later
├── providers: LlmProvider adapters and market-data providers, both BYOK
└── UI: mobile, desktop, and web, including agent-configured analytics widgets
```

## Storage model

A tracker lives in a state directory — the same layout on a local folder and a cloud provider folder: the canonical spreadsheet (single source of truth — a local `.xlsx` workbook, or the cloud provider's native spreadsheet document addressed by its document ID and revision, never an `.xlsx` mirror beside it), `profile.yaml`, `config/` (provider config and mapping profiles, `key_ref` references only), `imports/inbox/` and `imports/processed/`, rotated `backups/`, and a write-intent `journal/`. The [spreadsheet format](spreadsheet-format.md#state-directory) fixes this layout; the same document remains the precise workbook contract.

Adapters declare capabilities: `canWrite`, `atomicWrite`, `survivesCrash`, `persistentAccess: guaranteed | revocable`, `streamingRead`, and their revision model. Features gate on capabilities, never on scattered platform conditionals. The web client never writes local files — a local file on web is a read-only snapshot, and a cloud document is the only writable source in a browser. User-facing wording: "the browser cannot safely save changes to a file on your disk — connect a cloud provider or use the desktop app."

Every write runs a journaled cycle: record intent in durable storage → snapshot to `backups/` → apply → verify by read-back → commit or roll back. A killed browser tab or mobile process is a normal case, not an exception: the next open checks the pending intent against the source revision and recovers. Mobile local mode lives in the app sandbox; user-chosen external directories are supported but declared `revocable`, with graceful re-authorization that never loses state.

## Boundaries

- Initially the app opens one tracker at a time. Personal tracking and goals need no household setup. Optional family features add members, joint accounts, and shared goals; a later household view may read approved contributions from separate trackers.
- A tracker uses one source of truth: a local workbook or one cloud spreadsheet — never both, and no automatic two-way sync.
- Prioritize streaming XLSX loading and measured reporting improvements. A disk-backed SQLite cache is conditional on demonstrated need, remains rebuildable from the selected source, and belongs to Flutter. An expendable web/mobile cache of normalized records, tagged with the source revision, may protect against offline gaps and rate limits; losing it never loses data. See [large-workbook handling](flutter-architecture.md#large-workbooks) and [cache constraints](flutter-architecture.md#conditional-sqlite-cache).
- Named investment portfolios group accounts within that tracker. Individual and combined reports reuse the finance engine and count each included account once; see [portfolio rules](product.md#investment-portfolios).
- The LLM proposes; the core computes, validates, and writes. An LLM never calculates a figure and never writes directly. Everything that displays numbers works and is tested without an LLM.
- Data quality is never faked: unknown values are never zero; incomplete reports are withheld or explicitly labeled; reports never mix price/FX providers; deduplication never relies on date and amount alone; missing transfer legs or settlements are never invented.
- Neither the app nor the agent issues personal recommendations of specific financial instruments; see [LLM boundaries](privacy-and-llm.md#llm-analytics).
- Ownership does not enforce privacy; shared-file access exposes its included records. Separate-source consolidation follows the [one-way consolidation rules](product.md#separate-trackers-and-consolidation-later).
- Refresh and editing trigger monitoring in the open app; quote refresh is always an explicit user action. Continuous background monitoring is deferred.
- Spreadsheet customisation is user-controlled. The app normalizes a compatible custom schema for its deterministic finance engine, then builds an explicitly approved, scoped snapshot for analytics and LLMs.

## Domain tool layer

The domain is exposed as a typed tool API, useful and testable on its own, before and without any LLM:

- **Read tools**: reports (monthly cash flow, as-of net worth, portfolio summaries), document schema, validation errors, goal progress.
- **Proposal tools**: patches to document structure (sheet, column, source mapping) and to records (transaction, trade, allocation, goal). Every patch passes core validation and renders as a before/after diff.
- **Analytics tools**: parameterized queries computed by the core; interpretation is left to the caller.

The API surfaces all data-quality state (data-through, staleness, incompleteness) and structurally cannot fabricate data. No instrument-recommendation tool exists.

## Schema customisation

Users may customise their spreadsheet schema through a declarative source mapping profile and configure every feature widget through separate presentation settings. Mapping setup works without an LLM. Source mappings normalize records once for the canonical finance engine; widgets select report scopes and display options over its results. Unknown or invalid mapped data must not appear as zero. See [mapping requirements](spreadsheet-format.md#custom-schemas-and-mappings) and [widget configuration](ui.md#widget-configuration).

An LLM may propose a schema migration, but it never applies one directly.

```text
LLM proposal → compatibility check → user reviews diff → backup → apply → new schema version
```

The app validates a proposed migration, previews affected rows and parsing failures, creates a backup, and requires confirmation before it changes the workbook or cloud spreadsheet. Analytics and LLMs receive only an explicitly approved, scoped snapshot; they never receive the canonical tracker document or raw spreadsheet columns.

## Statement imports

Pipeline: a file arrives in `imports/inbox/` — on desktop by folder or picker, on mobile via the share sheet (iOS Share Extension / Android intent-filter for CSV/XLSX/XML) or an in-app picker → a mapping profile is selected or auto-detected → streamed parsing (a contract requirement: previews are paged, never whole-file-in-memory) → a normalized-record preview with actionable errors → confirmation → journaled write → the original moves to `processed/`, and the batch is recorded in the `imports` tab.

Rules: deduplicate by the bank identity defined in the [spreadsheet format](spreadsheet-format.md); re-importing the same file is idempotent; broker adapters create both the trade and its linked settlement transaction, or mark the settlement incomplete.

First formats: generic CSV/XLSX via mapping profiles (covers most banks), Interactive Brokers Flex Query XML, Trading212 and Revolut CSV. Mapping profiles are plain YAML in `config/mappings/`; the agent can later draft them from a sample statement, always via preview and confirmation.

## LLM providers and the agent

`LlmProvider` abstracts OpenAI-compatible APIs, Anthropic, Gemini, and local models (Ollama) behind a neutral internal tool-calling format with per-provider adapters, so models can switch mid-session. Providers declare capabilities (structured output, context size); the agent adapts its strategy — fewer tools and more stepwise confirmation for weaker models. Models without tool calling or structured output get plain chat only.

Keys are BYOK in the platform secure store; config files hold only `key_ref` references, so syncing the state directory between the user's own devices leaks no credentials. The directory is still not a sharing boundary: `profile.yaml`, original statements in `imports/`, `backups/`, and `journal/` all contain financial data, and sharing the folder shares them all — see [household sharing](privacy-and-llm.md#household-sharing). Flutter never contains a developer-provided provider API key, and the model never receives storage credentials or generic spreadsheet-write tools.

The agent loop: proposal → core validation → user confirmation → adapter write → read-back verification. Every applied patch is recorded in an action journal with per-change rollback (provider revision history for cloud; backups for local). The agent updates the user profile only through confirmed deltas; see [privacy and LLM boundaries](privacy-and-llm.md) and [chat, skills, and delivery actions](chat-and-skills.md).

This in-app provider abstraction supersedes the earlier local-companion/LiteLLM routing; [local-companion.md](local-companion.md) is retained for reference only.

## Market data

Quote providers are BYOK with defaults chosen so the app works out of the box with zero keys. Resolution order: `instrument.price_provider` → per-type default → global default. `config/providers.yaml` holds defaults, per-provider `key_ref`, and rate limits.

| Class | Keyless default | BYOK options |
| --- | --- | --- |
| FX | Frankfurter (ECB rates) | exchangerate.host, Open Exchange Rates |
| Crypto | CoinGecko | CoinMarketCap, Binance public API |
| Stocks/ETF | none exists — the app asks for a key | Twelve Data (suggested default), Alpha Vantage, Finnhub, EODHD, Polygon.io |
| Bonds/untraded | `manual` provider (user-entered price, recorded with `provider=manual` and a date) | — |
| Metals | — | metals.dev, FX providers (XAU/XAG) |

Quote refresh is always an explicit user action with progress and `retrieved_at` — this also sidesteps mobile background-execution limits. A provider failure makes affected reports incomplete per the existing rules; stale observations are shown dated, never silently substituted; reports never mix providers.

## User profile

`profile.yaml` stores summarized goals and priorities, risk tolerance, reporting preferences, accepted and dismissed suggestions, and communication style — never raw transactions. It is human-readable and user-editable, updated only through confirmed deltas the agent proposes after sessions, and injected into agent sessions only as the selected [data-sharing mode](privacy-and-llm.md#llm-analytics) permits. Dismissals are respected while their supporting facts remain unchanged.

## Portable config bundle

`finance-tracker-config.ftconfig` exports `bundle_version`, the providers config without keys, mapping profiles, and optionally the profile and widget-instance definitions the user marked portable. A portable widget-instance definition is the materialized query: title, data scope, fields, grouping, and reporting options, keyed by its stable instance ID. Device presentation — visibility, order, and position — is never exported; see [widget configuration](ui.md#widget-configuration). Never included: data, API keys, device-specific presentation. Channels: a file via share sheet or picker, the cloud directory itself (the primary path), or a QR code for small bundles. Import is a merge with diff preview and explicit confirmation: portable widget instances merge by stable instance ID, device-local presentation settings are never overwritten, older apps refuse newer bundle versions, and after import one screen lists missing keychain keys. The bundle is a deliberate one-shot action, mirroring the ban on two-way source sync; continuous config consistency comes from the cloud folder's revision model.
