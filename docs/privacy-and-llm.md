# Privacy and LLM boundaries

## Storage

Local workbook data stays on the user's device. Cloud spreadsheet data — Google Sheets first, Microsoft Excel over OneDrive/SharePoint planned — is governed by the user's provider account and sharing settings; no cloud provider is end-to-end encrypted by this project.

API keys are BYOK and live only in the platform secure store. Synced state — the tracker's state directory, including `config/providers.yaml` and mapping profiles — holds only `key_ref` references, never a key, so syncing it between the user's own devices leaks no credentials. That does not make the directory shareable: `profile.yaml`, original statements in `imports/`, `backups/`, and `journal/` contain financial data, so granting someone access to a tracker folder discloses them all. Keep records meant to stay private in a separate, unshared tracker, per the household-sharing rules below.

The app requests only the Google Sheets/Drive permissions required to open or create the selected tracker. The app must clearly show the selected spreadsheet before it reads or writes it.

## Household sharing

Member and account ownership fields describe attribution; they do not enforce access control. Anyone with access to a shared workbook or Sheet can access its included records. App filters, hidden tabs, and protected ranges do not make those records private. Google explicitly warns that [sheet protection is not a security measure](https://support.google.com/docs/answer/1218656?hl=en-GB).

Keep private records in separate files. Later consolidation accepts only contributions approved by their owner for household sharing. Sharing a summary limits the reports the app can produce; it must not infer hidden transactions or silently request wider access. Exported household reports contain only the approved scope. Removing a source stops future access but cannot retract copies already shared.

Permission to include data in a household view does not grant permission to send it to an LLM. Each contributor must approve that use and scope before their data enters an AI snapshot; otherwise exclude it and label the remaining coverage.

## LLM analytics

An LLM receives only an explicitly approved, computed finance snapshot: totals, periods, categories, selected holdings, and selected goal/action summaries, with freshness and completeness markers. It does not receive a raw bank file, OAuth token, or unrestricted spreadsheet access.

A request to a provider is constructed only after a data-sharing mode is selected; the mode bounds every payload — snapshot, profile, and lineage alike. No field outside the selected mode's column may enter a request, whatever the feature that builds it:

| Mode | Snapshot | Profile (`profile.yaml`) | Lineage ("explain" traces) |
| --- | --- | --- | --- |
| Full data | The approved scoped snapshot: amounts, periods, categories, selected holdings, goal/action summaries, data-quality markers | Goals and priorities, risk tolerance, reporting preferences, accepted/dismissed suggestions, communication style | The computed trace behind the selected figure: redacted lineage rows within the approved scope, the FX rate, and the price provider |
| Aggregates only | Totals per period, category, and portfolio only — no individual transactions, payees, or descriptions | Same as full data | Per-step totals, providers, and rates only — never source rows |
| Structure without amounts | Schema, tab/column structure, entity counts, and data-quality markers — no amounts, balances, or holdings | Reporting preferences and communication style only — no goal amounts or priorities | Computation steps and providers only — no amounts or rows |

A redacted lineage row carries only the fields the snapshot contract already permits: booking date, signed amount and currency, category, and the account's per-snapshot pseudonym. It never carries payee, description, counterparty, bank identity (`source`, `source_id`, `row_fingerprint`), row UUIDs, real account names, or file paths — the same exclusions as the snapshot itself. Full row detail stays in the app's own lineage UI.

The user profile stores summarized intent — goals, priorities, preferences — never raw transactions. It is updated only through confirmed deltas the agent proposes and is injected into an agent session only as the selected mode's profile column permits.

The client may provide deterministic budgeting guidance for user-chosen goals, such as a required contribution or a spending change to review. An LLM may explain these results, assumptions, and alternatives. It must not invent financial inputs, calculate authoritative goal progress or affordability, create transactions, transfer money, execute trades, or present investment, tax, or legal recommendations as professional advice. Goals and actions work without an LLM, and invalid, stale, or incomplete inputs block affected suggestions.

Neither the app nor the agent issues personal recommendations of specific financial instruments ("buy X", "X is better for you"). Permitted: budgeting, deterministic observations from the user's own data, and arithmetic on goals the user defined. Disclaimers appear in onboarding, investment reports, and agent responses touching instruments. The tool layer contains no instrument-recommendation tool; prohibited phrasings and prompt-level refusal tests are documented and run as regression checks — asked "what should I buy?", the agent declines with an explanation and offers permitted analytics instead. Obtain legal review per target jurisdiction before a public release of investment features.

## Local and cloud models

The app talks to models through its `LlmProvider` abstraction: OpenAI-compatible APIs, Anthropic, Gemini, and local models such as Ollama, with per-provider adapters so models can switch mid-session. On every native platform (iOS, Android, desktop), the user configures a cloud provider with their own API key, a self-hosted HTTPS endpoint with its own token, or a local OpenAI-compatible endpoint; the app sends the approved snapshot and chat request directly to the selected endpoint. Cloud and self-hosted endpoints require validated TLS. A local endpoint such as Ollama or LM Studio is loopback-only (`127.0.0.1`, `::1`, or `localhost`) and may use plain HTTP on that interface; an endpoint on any other address is never treated as local and must meet the self-hosted TLS requirements. A self-hosted endpoint may be the user's LiteLLM server or an OpenAI-compatible LLM server; no endpoint ever receives storage credentials. The earlier companion-routed desktop/web path is superseded by this in-app abstraction.

The app clearly labels every chat as **Local**, **Cloud**, or **Self-hosted** and shows the selected provider and model. It never silently changes provider type.

Before a chat starts, the app checks model capabilities. Models without tool calling or structured output may provide plain chat only; proposal tools are disabled, and the agent uses fewer tools and more stepwise confirmation for weaker models. Only the deterministic core can apply a user-confirmed proposal, and every applied patch is journaled with per-change rollback.

## Saved chat and external agents

Saved conversations, summaries, and referenced results can contain financial data after an approved snapshot expires. Snapshot expiry does not erase transcripts or copies already sent to a provider or external agent. Treat saved history as sensitive user data, separate from the rebuildable tracker cache; see [conversation storage](chat-and-skills.md#conversation-storage).

When chat ships, clearly offer local saved-history and session-only modes. Explain what is persisted before enabling saved history, and provide retention, export, and deletion controls. Session-only mode must not persist transcripts or summaries locally; provider-side retention is separate and must not be described as session-only. Keep persistent history in app-private storage, define backup behavior, and assess encryption at rest; ordinary SQLite does not itself encrypt messages. Credentials remain in their dedicated secure stores.

Delete dependent summaries and local context caches when their source messages are deleted; invalidate prepared requests that still contain them. Reopening history does not authorize sending it to a new provider or broadening its approved scope. Make renewed disclosure explicit before resending, including contributor approval for household data. Historical answers retain their original scope and as-of markers and never substitute for current calculations.

External agents such as Codex, Claude Code, and Antigravity control their own transcripts, tools, and retention. Snapshot approval authorizes only the scoped data release; it does not make the external host a controlled sandbox. Explain that disconnecting or deleting local history cannot retract external copies. [Skills](chat-and-skills.md#portable-skills-controlled-execution) carry instructions, never credentials or financial records, and cannot grant additional access.

## Credentials

These are requirements for the planned integrations; Google authorization, AI connections, and credential storage are not implemented yet.

### Google Sheets

Use user OAuth authorization for private trackers. An API key alone does not authorize access to private spreadsheets. OAuth client IDs identify the app and may be distributed; access and refresh tokens are secrets. Register the appropriate client for each platform and configure its authorized origins, redirects, or app identity. Never ship a service-account private key or rely on an embedded OAuth client secret to protect a distributed app. See [Google's credential guidance](https://developers.google.com/workspace/guides/create-credentials).

- On native platforms, use supported Google authorization SDKs or system-browser flows, with authorization code and PKCE where applicable. Keep persistent tokens in platform secure storage. See [installed-app OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).
- On web, use [Google Identity Services](https://developers.google.com/identity/oauth2/web/guides/use-token-model) for user-present access, keep access tokens in memory, and request authorization again when required. Do not persist refresh tokens in browser storage. A persistent server-side authorization flow would require a separately designed trusted component.
- Prefer explicit file selection with Picker and `drive.file` where appropriate. It restricts access to selected files but permits writing. `spreadsheets.readonly` prevents writes but grants access to all spreadsheets the user can access; it is not a selected-file-only permission. Choose and explain this tradeoff for the feature being delivered, without adding broad Drive scopes by default. See [Sheets scopes](https://developers.google.com/workspace/sheets/api/scopes).
- If Picker requires a browser API key, restrict it to the required APIs and authorized origins. Treat it as exposed client configuration, separate from AI provider keys; follow [Google's API-key guidance](https://docs.cloud.google.com/docs/authentication/api-keys-best-practices).

Provide disconnect and token-revocation handling, and clear locally stored credentials when disconnected. Google credentials never enter a workbook, tracker cache, AI snapshot, or any LLM request. Permission to open a tracker does not authorize sending it to a model.

### AI providers and self-hosted endpoints

Never embed an app-owned OpenAI, Anthropic, or other provider API key in a Flutter build. Obfuscation, `.env` assets, `--dart-define`, and encryption with a bundled decryption key cannot hide a secret from the distributed client. [OpenAI](https://developers.openai.com/api/reference/overview) directs developers to keep keys out of client code; [Anthropic's SDK](https://github.com/anthropics/anthropic-sdk-typescript) disables browser access by default because it exposes credentials.

| Route | Credential ownership and storage |
| --- | --- |
| Native BYOK (mobile and desktop) | The user enters their own provider key. Store it only in the platform secure store, reference it from config as a `key_ref`, and send it directly to the selected provider over validated HTTPS. |
| Native self-hosted (mobile and desktop) | Store the user's endpoint token in the platform secure store and send it only to that configured HTTPS endpoint. The endpoint receives no storage credentials. |
| Web | Direct BYOK and chat remain unavailable under the current architecture. Browser storage cannot hide a long-lived provider key from executing application scripts. |
| App-owned provider account | Requires a trusted gateway with user authentication, request limits, and spending controls. A product-operated gateway would be an explicit architecture expansion. |

For native user tokens, use Apple Keychain or token encryption with an Android Keystore-protected encryption key. Desktop storage should use the OS credential store. Secure storage protects credentials at rest; a bearer token still enters process memory when used. Native BYOK limits exposure to the user's own account and is not a guarantee against a compromised device. See [Apple Keychain](https://developer.apple.com/documentation/security/keychain-services) and [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

Redact credentials from logs, crash reports, analytics, and request diagnostics. Keep them out of spreadsheets, database caches, URLs, and model input. Support credential deletion and replacement, and explain provider-side revocation. Scope each credential to its intended endpoint; do not forward it across an origin-changing redirect. Require valid TLS for remote endpoints and never disable certificate validation; the only exception is a loopback-only local model endpoint, which may use plain HTTP on the loopback interface alone. Provider credentials grant no additional snapshot scope or authority to change financial data.
