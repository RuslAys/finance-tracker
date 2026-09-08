# Architecture

## Goal

The client-first financial helper supports individual use with optional family features. Flutter owns finance rules, import validation, personal and household reports, goal progress, and deterministic budgeting suggestions. User data is not stored in a product-operated database. See [product rules and delivery order](product.md).

Only the finance domain and read-only sample UI are implemented. Storage, household features, goals, consolidation, and the companion below describe planned work.

## Components

```text
Flutter application
├── domain: validation, balances, cash flow, holdings, goals, suggestions
├── storage: local workbook or Google Sheets
└── UI: mobile, web, and desktop

Optional local companion
├── ADK 2.x analytics workflow over a computed read-only snapshot
├── MCP tools for Codex, Claude, and compatible clients
└── LLM provider connection for in-app chat
```

## Boundaries

- Initially the app opens one tracker at a time. Personal tracking and goals need no household setup. Optional family features add members, joint accounts, and shared goals; a later household view may read approved contributions from separate trackers.
- A tracker uses one source of truth: a local workbook or a Google Sheet.
- Import/export moves data between sources; v1 has no automatic two-way sync.
- The optional companion has no write capability and never modifies transactions or spreadsheets.
- Financial calculations, goal allocations, and suggestion rules are deterministic client code. An LLM can explain calculated results but cannot be the authority for balances, gains, goal progress, or affordability.
- Ownership does not enforce privacy; shared-file access exposes its included records. Separate-source consolidation follows the [one-way consolidation rules](product.md#separate-trackers-and-consolidation-later).
- Refresh and editing trigger monitoring in the open app. Continuous background monitoring is deferred; the companion never refreshes tracker sources.
- Spreadsheet customisation is user-controlled. The app normalizes a compatible custom schema for its deterministic finance engine, then builds an explicitly approved, scoped snapshot for analytics, MCP tools, and LLMs.
- Companion access, pairing, and snapshot lifetime follow the [local companion contract](local-companion.md#access-and-snapshot-lifetime).

## Schema customisation

Users may customise their spreadsheet schema. An LLM may propose a schema migration, but it never applies one directly.

```text
LLM proposal → compatibility check → user reviews diff → backup → apply → new schema version
```

The app validates a proposed migration, previews affected rows and parsing failures, creates a backup, and requires confirmation before it changes the workbook or Google Sheet. MCP tools and LLMs receive only an explicitly approved, scoped snapshot; they never receive the canonical tracker document or raw spreadsheet columns.

## LLM providers

Mobile cloud chat uses bring-your-own-key (BYOK): the user explicitly configures a cloud provider and the native Flutter client calls it over TLS. The key is stored only in the platform secure store and is never packaged into the app. The cloud provider receives only the approved finance snapshot and chat request.

```text
Flutter mobile chat → selected cloud provider
                     or user-hosted HTTPS LLM endpoint
```

The optional local companion provides the desktop/web path and a single LiteLLM interface for local and cloud models:

```text
Flutter chat → local ADK companion → LiteLLM
                                  ├── local OpenAI-compatible endpoint
                                  │   └── Ollama or LM Studio
                                  └── cloud provider
                                      └── OpenAI, Claude, or Gemini
```

The provider routes are `cloud_byok` and `self_hosted` on native mobile, and `local_openai_compatible` and `cloud_companion` through the companion. A `self_hosted` profile is a user-configured HTTPS endpoint, such as the user's LiteLLM server or OpenAI-compatible LLM server. The native app stores its endpoint token in the platform secure store, requires a valid TLS certificate, and sends it only to that endpoint. The server never becomes the tracker data source or receives Google credentials. `cloud_byok` uses the user's key in the native platform secure store; `cloud_companion` uses the companion's local secret store. Flutter never contains a developer-provided provider API key.

Mobile chat is available only for a user-configured cloud or self-hosted provider. Local-model chat on mobile remains unavailable in v1. Desktop chat and web chat served from the companion's own loopback origin require a reachable companion; a separately hosted web build cannot use chat.

The model never gets Google credentials or generic spreadsheet-write tools. It may return a schema-migration proposal only; Flutter validates it against the canonical tracker, previews the exact change, requires confirmation, and then applies it through the selected storage adapter.

## ADK

Use ADK 2.x in the companion. V1 is one graph-based analytics workflow: validate the approved snapshot, call the selected model through LiteLLM, then return an explanation. It has no agent delegation, write tools, or autonomous loops. Add further workflow nodes only for a concrete, user-visible analytics task.
