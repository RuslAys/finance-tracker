# Privacy and LLM boundaries

## Storage

Local workbook data stays on the user's device. Google Sheets data is governed by the user's Google account and sharing settings; Google Sheets is not end-to-end encrypted by this project.

The app requests only the Google Sheets/Drive permissions required to open or create the selected tracker. The app must clearly show the selected spreadsheet before it reads or writes it.

## Household sharing

Member and account ownership fields describe attribution; they do not enforce access control. Anyone with access to a shared workbook or Sheet can access its included records. App filters, hidden tabs, and protected ranges do not make those records private. Google explicitly warns that [sheet protection is not a security measure](https://support.google.com/docs/answer/1218656?hl=en-GB).

Keep private records in separate files. Later consolidation accepts only contributions approved by their owner for household sharing. Sharing a summary limits the reports the app can produce; it must not infer hidden transactions or silently request wider access. Exported household reports contain only the approved scope. Removing a source stops future access but cannot retract copies already shared.

Permission to include data in a household view does not grant permission to send it to an LLM. Each contributor must approve that use and scope before their data enters an AI snapshot; otherwise exclude it and label the remaining coverage.

## LLM analytics

An LLM receives only an explicitly approved, computed finance snapshot: totals, periods, categories, selected holdings, and selected goal/action summaries, with freshness and completeness markers. It does not receive a raw bank file, OAuth token, or unrestricted spreadsheet access.

The client may provide deterministic budgeting guidance for user-chosen goals, such as a required contribution or a spending change to review. An LLM may explain these results, assumptions, and alternatives. It must not invent financial inputs, calculate authoritative goal progress or affordability, create transactions, transfer money, execute trades, or present investment, tax, or legal recommendations as professional advice. Goals and actions work without an LLM, and invalid, stale, or incomplete inputs block affected suggestions.

## Local and cloud models

On iOS and Android, a user may configure a cloud provider with their own API key, or a self-hosted HTTPS LLM endpoint with its own endpoint token. The native app sends the approved snapshot and chat request directly to the selected endpoint over TLS. A self-hosted endpoint may be the user's LiteLLM server or an OpenAI-compatible LLM server; it never receives Google credentials. A local model runs through the optional companion to a user-configured OpenAI-compatible endpoint, such as Ollama or LM Studio. Desktop and companion-served web chat may also use a cloud provider through the companion.

The app clearly labels every chat as **Local**, **Cloud**, or **Self-hosted** and shows the selected provider and model. It never silently changes provider type.

Before a chat starts, the app or companion checks model capabilities. Models without tool calling or structured output may provide plain chat only; schema-migration proposals are disabled. The companion never has write capability; only the Flutter app can apply a user-confirmed proposal.

## Saved chat and external agents

Saved conversations, summaries, and referenced results can contain financial data after a companion snapshot expires. Snapshot expiry does not erase transcripts or copies already sent to a provider or external agent. Treat saved history as sensitive user data, separate from the rebuildable tracker cache; see [conversation storage](chat-and-skills.md#conversation-storage).

When chat ships, clearly offer local saved-history and session-only modes. Explain what is persisted before enabling saved history, and provide retention, export, and deletion controls. Session-only mode must not persist transcripts or summaries locally; provider-side retention is separate and must not be described as session-only. Keep persistent history in app-private storage, define backup behavior, and assess encryption at rest; ordinary SQLite does not itself encrypt messages. Credentials remain in their dedicated secure stores.

Delete dependent summaries and local context caches when their source messages are deleted; invalidate prepared requests that still contain them. Reopening history does not authorize sending it to a new provider or broadening its approved scope. Make renewed disclosure explicit before resending, including contributor approval for household data. Historical answers retain their original scope and as-of markers and never substitute for current calculations.

External agents such as Codex, Claude Code, and Antigravity control their own transcripts, tools, and retention. Pairing and snapshot approval authorize only the companion's scoped data release; they do not make the external host a controlled sandbox. Explain that disconnecting or deleting local history cannot retract external copies. [Skills](chat-and-skills.md#portable-skills-controlled-execution) carry instructions, never credentials or financial records, and cannot grant additional access.

## Credentials

These are requirements for the planned integrations; Google authorization, AI connections, and credential storage are not implemented yet.

### Google Sheets

Use user OAuth authorization for private trackers. An API key alone does not authorize access to private spreadsheets. OAuth client IDs identify the app and may be distributed; access and refresh tokens are secrets. Register the appropriate client for each platform and configure its authorized origins, redirects, or app identity. Never ship a service-account private key or rely on an embedded OAuth client secret to protect a distributed app. See [Google's credential guidance](https://developers.google.com/workspace/guides/create-credentials).

- On native platforms, use supported Google authorization SDKs or system-browser flows, with authorization code and PKCE where applicable. Keep persistent tokens in platform secure storage. See [installed-app OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).
- On web, use [Google Identity Services](https://developers.google.com/identity/oauth2/web/guides/use-token-model) for user-present access, keep access tokens in memory, and request authorization again when required. Do not persist refresh tokens in browser storage. A persistent server-side authorization flow would require a separately designed trusted component.
- Prefer explicit file selection with Picker and `drive.file` where appropriate. It restricts access to selected files but permits writing. `spreadsheets.readonly` prevents writes but grants access to all spreadsheets the user can access; it is not a selected-file-only permission. Choose and explain this tradeoff for the feature being delivered, without adding broad Drive scopes by default. See [Sheets scopes](https://developers.google.com/workspace/sheets/api/scopes).
- If Picker requires a browser API key, restrict it to the required APIs and authorized origins. Treat it as exposed client configuration, separate from AI provider keys; follow [Google's API-key guidance](https://docs.cloud.google.com/docs/authentication/api-keys-best-practices).

Provide disconnect and token-revocation handling, and clear locally stored credentials when disconnected. Google credentials never enter a workbook, tracker cache, AI snapshot, or the AI companion. Permission to open a tracker does not authorize sending it to a model.

### AI providers and self-hosted endpoints

Never embed an app-owned OpenAI, Anthropic, or other provider API key in a Flutter build. Obfuscation, `.env` assets, `--dart-define`, and encryption with a bundled decryption key cannot hide a secret from the distributed client. [OpenAI](https://developers.openai.com/api/reference/overview) directs developers to keep keys out of client code; [Anthropic's SDK](https://github.com/anthropics/anthropic-sdk-typescript) disables browser access by default because it exposes credentials.

| Route | Credential ownership and storage |
| --- | --- |
| Native mobile `cloud_byok` | The user enters their own provider key. Store it only in platform secure storage and send it directly to the selected provider over validated HTTPS. |
| Native mobile `self_hosted` | Store the user's endpoint token in platform secure storage and send it only to that configured HTTPS endpoint. The endpoint receives no Google credentials. |
| Desktop and companion-served web | Provider keys remain in the companion's local secret store. The client authenticates through the [companion pairing contract](local-companion.md#access-and-snapshot-lifetime); it never receives the provider key. |
| Separately hosted web | Direct BYOK and chat remain unavailable under the current architecture. Browser storage cannot hide a long-lived provider key from executing application scripts. |
| App-owned provider account | Requires a trusted gateway with user authentication, request limits, and spending controls. Distributing the app-owned key through a companion installation does not protect it from that installation's owner. A product-operated gateway would be an explicit architecture expansion. |

For native user tokens, use Apple Keychain or token encryption with an Android Keystore-protected encryption key. Desktop companion storage should use the OS credential store. Secure storage protects credentials at rest; a bearer token still enters process memory when used. Native BYOK limits exposure to the user's own account and is not a guarantee against a compromised device. See [Apple Keychain](https://developer.apple.com/documentation/security/keychain-services) and [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

Redact credentials from logs, crash reports, analytics, and request diagnostics. Keep them out of spreadsheets, database caches, URLs, and model input. Support credential deletion and replacement, and explain provider-side revocation. Scope each credential to its intended endpoint; do not forward it across an origin-changing redirect. Require valid TLS for remote endpoints and never disable certificate validation. Only the authenticated loopback companion uses the local transport defined in its contract. Provider credentials grant no additional snapshot scope or authority to change financial data.
