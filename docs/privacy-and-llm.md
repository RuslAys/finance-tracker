# Privacy and LLM boundaries

## Storage

Local workbook data stays on the user's device. Google Sheets data is governed by the user's Google account and sharing settings; Google Sheets is not end-to-end encrypted by this project.

The app requests only the Google Sheets/Drive permissions required to open or create the selected tracker. The app must clearly show the selected spreadsheet before it reads or writes it.

## LLM analytics

An LLM receives only an explicitly approved, computed finance snapshot: totals, periods, categories, and selected holdings. It does not receive a raw bank file, OAuth token, or unrestricted spreadsheet access.

The model may explain trends and caveats. It must not create transactions, transfer money, or give instructions presented as personalized financial advice.

## Local and cloud models

On iOS and Android, a user may configure a cloud provider with their own API key, or a self-hosted HTTPS LLM endpoint with its own endpoint token. The native app sends the approved snapshot and chat request directly to the selected endpoint over TLS. A self-hosted endpoint may be the user's LiteLLM server or an OpenAI-compatible LLM server; it never receives Google credentials. A local model runs through the optional companion to a user-configured OpenAI-compatible endpoint, such as Ollama or LM Studio. Desktop and companion-served web chat may also use a cloud provider through the companion.

The app clearly labels every chat as **Local**, **Cloud**, or **Self-hosted** and shows the selected provider and model. It never silently changes provider type.

Before a chat starts, the app or companion checks model capabilities. Models without tool calling or structured output may provide plain chat only; schema-migration proposals are disabled. The companion never has write capability; only the Flutter app can apply a user-confirmed proposal.

## Credentials

Never embed an app-owned OpenAI, Anthropic, or other provider API key in a Flutter build. In native mobile BYOK mode, the user enters their own provider or self-hosted-endpoint token and the app stores it only in the platform secure store; it is unavailable on Flutter web. Self-hosted endpoints must use HTTPS with a valid certificate. A user-controlled local companion may instead own provider credentials and exposes only an authenticated loopback interface to the app. An app-owned cloud-provider account requires a backend or reachable companion; it cannot be secured in a mobile or web build.
