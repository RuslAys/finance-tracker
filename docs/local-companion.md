# Local companion

The local companion is optional. It is not a hosted backend and does not become the finance data source of truth.

## Responsibilities

- Run an ADK 2.x analytics workflow on a computed, read-only snapshot supplied by the Flutter app.
- Hold LLM provider credentials locally.
- Expose narrow, read-only MCP tools such as cash-flow, spending, and holdings summaries.
- Connect to either a user-configured local OpenAI-compatible endpoint or a selected cloud provider.
- Stream in-app chat responses and report the selected model's capabilities.

## Non-responsibilities

- Persisting the user's tracker data.
- Direct spreadsheet modification or any write-capable MCP tool.
- Automatic transaction imports or financial actions.

The Flutter app alone may apply user-confirmed edits and migrations through its storage adapter.

## Access and snapshot lifetime

The companion binds its HTTP and HTTP-MCP listeners to `127.0.0.1` only. A user-confirmed pairing flow mints a random, per-client token of at least 128 bits from a CSPRNG, displays it once for the client to store, and lets the user revoke that client later. Every request, including snapshot publication, must authenticate with its token. Token comparison is constant-time; failed authentication attempts are rate-limited with exponential backoff.

When an `Origin` header is present, it must be the companion's loopback origin; the companion rejects any other origin and never enables permissive CORS. Native MCP clients do not send `Origin` and authenticate with their pairing token. Web chat is therefore available only from a Flutter web build served by the companion's loopback origin, not from an arbitrary hosted website.

The Flutter app publishes an explicitly approved snapshot to memory. It includes `tracker_id` and an `as_of` UTC timestamp. The app sends a heartbeat every five minutes while it is open; a new snapshot replaces the old one. The companion clears the snapshot when the app explicitly closes or after two missed heartbeats. MCP tools cannot load or refresh tracker data: they require the Flutter app to remain open, fail closed with `no active snapshot` when it is not, and otherwise return the `tracker_id` and `as_of` marker with every result.

## Provider behaviour

The companion uses LiteLLM as its one provider interface for local and cloud models. It defaults to a configured local model and never changes to a cloud provider without the user's explicit selection. Cloud API keys remain in the companion's local secret store.

ADK 2.x runs a single deterministic workflow in v1: validate the approved snapshot, request an explanation through LiteLLM, and stream the result. Multi-agent delegation, autonomous loops, and write tools are out of scope until they solve a specific user task.
