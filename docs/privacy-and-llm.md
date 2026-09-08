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

## Credentials

Never embed an app-owned OpenAI, Anthropic, or other provider API key in a Flutter build. In native mobile BYOK mode, the user enters their own provider or self-hosted-endpoint token and the app stores it only in the platform secure store; it is unavailable on Flutter web. Self-hosted endpoints must use HTTPS with a valid certificate. A user-controlled local companion may instead own provider credentials and exposes only an authenticated loopback interface to the app. An app-owned cloud-provider account requires a backend or reachable companion; it cannot be secured in a mobile or web build.
