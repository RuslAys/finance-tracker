# Spreadsheet format

Use the same workbook tabs and columns for a local `.xlsx` tracker and a Google Sheet. CSV is supported only as an import/export format because it cannot represent the related tables.

## Rules

- IDs are UUIDs; row numbers are never identifiers.
- Dates use `YYYY-MM-DD`.
- Monetary values use integer minor units. The `currencies.minor_unit` value defines the scale: `1234` means `12.34` for EUR (`2`), `1234` means `1234` for JPY (`0`), and `1234` means `1.234` for KWD (`3`).
- Fractional asset quantities are decimal strings, never binary floating-point values.
- The workbook contains no macros, formulas, or external links.
- Boolean fields are written as the lowercase text values `true` or `false`.
- Decimal strings use ASCII digits, an optional leading `-` for a nonzero value, and an optional decimal point: no leading `+`, no leading zeroes except `0`, and no trailing fractional zeroes. `0` is the only zero form; `-0` and `-0.0` normalize to `0`. `0.85` and `-0.85` are valid; `.85` is invalid. Thus `1.5`, `1.50`, and `1.500` normalize to `1.5`.

## Cell encoding and read normalization

All exact-value fields are written as text cells: UUIDs, ISO dates, RFC 3339 UTC timestamps, currency codes, booleans, `*_minor` amounts, `trades.units`, and `fx_rates.rate`. Google Sheets writes these strings with `RAW` input; XLSX writers set the cell type to text. This prevents Sheets and Excel from silently storing exact decimals or timestamps as IEEE-754 values.

Readers normalize legacy cell values before validation:

- Native Booleans and case-insensitive `TRUE`/`FALSE` text normalize to lowercase `true`/`false`.
- ISO date text is canonical. A numeric date serial is accepted only from a cell explicitly formatted as a date and is normalized using its source workbook date system and spreadsheet timezone; otherwise it is rejected.
- Timestamps are canonical RFC 3339 UTC text. Numeric timestamp serials are rejected because their timezone and precision cannot be recovered exactly.
- A numeric `*_minor` cell is accepted only when it is an exact safe integer. Numeric `trades.units` and `fx_rates.rate` cells are rejected because their original decimal precision cannot be recovered.

Any value that cannot be normalized exactly is a validation error; the app does not silently rewrite it.

## Tabs

### `_meta`

| key | value |
| --- | --- |
| `format_version` | `1` |
| `layout_version` | `1` |
| `mapping_version` | `1` |
| `tracker_id` | UUID |
| `base_currency` | ISO 4217 code |

`format_version` describes the canonical app model. `layout_version` describes the user-visible workbook or Sheet layout. `mapping_version` describes the active mapping configuration. A custom header rename changes `layout_version` and `mapping_version`, not `format_version`.

### `currencies`

`code, minor_unit`

Every currency used by `_meta.base_currency`, an account, transaction, trade, instrument, price, or either side of an `fx_rates` row must have one row. `minor_unit` is a non-negative integer using that currency's supported decimal scale.

### `accounts`

`id, name, type, currency, archived`

### `categories`

`id, name, parent_id, type`

`type` is `income`, `expense`, or `transfer`.

`parent_id` is blank or references another category with the same `type`. Category parent links must be acyclic.

### `transactions`

`id, account_id, booked_on, amount_minor, currency, payee, description, category_id, transfer_id, source, source_id, row_fingerprint, import_id, created_at`

Each account has one currency. A transaction's `currency` must equal its account currency. `amount_minor` is positive for money entering the account and negative for money leaving it. Income and expense categories may contain either sign: the normal income is positive and normal expense is negative, while the opposite sign is a reversal such as an income correction or merchant refund. Cash flow always uses the signed amount. Income reporting uses the category's signed sum; expense reporting uses its negated signed sum, so a positive refund reduces expense.

Rows whose `import_id` references an import other than `committed` are excluded from all balances, cash-flow, holdings, and analytics until their import commits or reconciliation removes them.

A `transfer_id` appears on exactly two `transfer` transactions in different accounts, with the same currency and amounts that sum to zero. Cross-currency cash transfers are not supported in v1.

`source_id` is the bank's stable transaction ID when available. The unique bank identity is `(account_id, source, source_id)`. `row_fingerprint` is the deterministic fallback identity defined below when the bank does not provide a stable ID.

`source` is a stable lowercase import-profile identifier matching `[a-z0-9][a-z0-9._-]{0,63}`, such as `revolut` or `manual`; it is never a filename, date, or upload path.

### `account_aliases`

`source, source_account_id, account_id`

The composite key is `(source, source_account_id)`. An import resolves its source account value through this table before it creates transaction or trade fingerprints. An unknown or ambiguous alias is a preview error; the user must select an existing account and create its alias before the import can commit. An import never mints an account UUID implicitly.

### `instruments`

`id, symbol, name, type, currency`

### `instrument_aliases`

`source, symbol, exchange, instrument_id`

The composite key is `(source, symbol, exchange)`. A trade import resolves its broker identifier through this table before it creates a fingerprint. An unknown or ambiguous alias is a preview error; the user must select or create the instrument and its alias before the import can commit. An import never mints an instrument UUID implicitly.

### `trades`

`id, account_id, instrument_id, traded_on, side, units, price_minor, fee_minor, currency, source, source_id, row_fingerprint, import_id`

`side` is `buy` or `sell`; `units` is always positive. Trade notional is `units × price_minor`, rounded once to a minor unit using decimal round-half-up. Fees are already minor units and are added to buy cost or deducted from sell proceeds.

V1 cost basis is FIFO per `(account_id, instrument_id, currency)`. Buy fees are capitalized into their lot cost; sell fees reduce proceeds. A sell cannot exceed available FIFO lots; short positions are not supported in v1.

`currency` is the settlement currency and must equal its account currency. `instruments.currency` is the instrument's reference currency and may differ. V1 requires a broker import to provide a price already converted to the settlement currency; it does not model foreign-currency settlement inside a trade.

### `prices`

`instrument_id, priced_on, price_minor, currency, provider`

The composite key is `(instrument_id, priced_on, currency, provider)`.

### `fx_rates`

`base_currency, quote_currency, priced_on, rate, provider`

`rate` is an exact decimal string representing quote-currency units per one base-currency unit. The composite key is `(base_currency, quote_currency, priced_on, provider)`.

Cross-currency reports select one `provider` and resolve an effective rate on the requested as-of date using this order: identity `1` when source equals target, direct `(source, target)`, reciprocal of `(target, source)`, then two legs through `_meta.base_currency`. Each direct or reciprocal leg uses the latest observation on or before the as-of date from that provider. No other triangulation, provider mixing, or rate selection is permitted. A missing leg makes the converted total unavailable; it must not be treated as zero.

Convert each stored decimal rate to the exact rational `unscaled_integer ÷ 10^fraction_digits`. A reciprocal swaps numerator and denominator; two legs multiply numerators and denominators. Do not materialize an intermediate decimal rate. To convert `amount_minor` from source currency with exponent `source_minor_unit` to target currency with exponent `target_minor_unit`, calculate the resulting rational `amount_minor × effective_rate × 10^target_minor_unit ÷ 10^source_minor_unit`, then divide and round once to the nearest target minor unit, with an exact half rounded away from zero.

### `imports`

`id, filename, sha256, source, status, expected_transaction_rows, expected_trade_rows, writer_token_hash, lease_updated_at, started_at, committed_at, override_of, override_reason`

`status` is `pending`, `committed`, `failed`, or `cancelled`. `writer_token_hash` is lowercase hexadecimal SHA-256 of a CSPRNG token with at least 128 bits of entropy. Only the importing app session holds the token; the shared workbook stores its hash. `lease_updated_at` is an RFC 3339 UTC timestamp. A lease expires five minutes after `lease_updated_at`. A user may set a pending import to `cancelled` to abort it before any staged rows are written. The app sets `failed` on a validation or write failure, and at the start of a user-confirmed discard of an import with staged rows. A file hash blocks re-import only when a matching row is `committed`. Failed or cancelled imports never block a retry.

An XLSX save writes data rows and the committed import row in one file replacement. Google Sheets has no equivalent multi-range transaction: it creates a `pending` import row with a token hash, expected row counts, and lease; the token holder refreshes the lease before each staged-row batch and before commit. Only a token whose SHA-256 matches the stored hash may stage rows or commit. Before commit, the writer re-reads its `pending` status, token hash, lease, row counts, and validation result, and aborts if its lease has expired or any value changed.

On every open and before every import, the app reconciles every transaction and trade whose `import_id` references a non-`committed` import, not only pending leases. An unexpired pending lease is left untouched; an expired lease blocks new imports and presents recovery. A user may explicitly discard an expired import: the app first marks it `failed`, then deletes only rows bearing that `import_id`. Rows referencing a `failed` import are deleted during reconciliation. Rows referencing a `cancelled` import are also deleted as a defensive recovery path for interrupted or legacy state, even though normal cancellation occurs before staging. If deletion is interrupted, the next reconciliation resumes it. A conflict is reported instead of deleting if a re-read finds the import committed. A writer finding a changed status or token hash stops without committing. A new import runs only after reconciliation is complete.

An explicit user-confirmed re-import may create a new import row with `override_of` set to the prior committed import ID and a non-empty `override_reason`. It still runs all row-level deduplication checks.

For a new import, an existing `(account_id, source, source_id)` identity within the same entity is a duplicate only when `source_id` is non-empty. A matching `row_fingerprint` is always presented as a duplicate candidate for user resolution before commit, whether or not the incoming row has a source ID; the import must not silently add it. These rules apply to both `transactions` and `trades`.

## Row fingerprints

`row_fingerprint` is lowercase hexadecimal SHA-256 over a versioned, length-prefixed UTF-8 sequence. Each field is encoded as its decimal UTF-8 byte length, an ASCII `:`, then its UTF-8 bytes; fields are concatenated in the listed order. This encoding cannot collide when field content contains delimiters.

Before encoding, UUIDs are lowercase, dates are ISO text, integers use base-10 without a leading `+` or leading zeroes, decimal strings use the canonical form above, currency is uppercase, and text uses Unicode NFC with leading/trailing Unicode whitespace removed and internal Unicode whitespace collapsed to one ASCII space. Empty values encode as length `0`.

- Transaction sequence: `finance-tracker:transaction-fingerprint:v1`, `account_id`, `booked_on`, `amount_minor`, `currency`, `payee`, `description`.
- Trade sequence: `finance-tracker:trade-fingerprint:v1`, `account_id`, `instrument_id`, `traded_on`, `side`, `units`, `price_minor`, `fee_minor`, `currency`.

The app stores a fingerprint for every imported transaction and trade, including rows with a `source_id`. This allows a later export without stable source IDs to detect an overlapping prior import. A migration that changes any canonical fingerprint input must recompute affected fingerprints, preview collisions, and receive user confirmation before commit.

## Local layout

```text
my-finance/
├── finance-tracker.xlsx
├── imports/       # optional original bank files
└── backups/       # dated workbook copies
```

Keep raw bank files outside version control.

## Custom schemas and mappings

The tabs and columns above are the canonical schema. A user may use a custom spreadsheet schema when a valid mapping converts it to the canonical model used by the app. `SnapshotBuilder` then produces the approved scoped data exposed to analytics, MCP tools, and LLMs.

An import selects exactly one `mapping_id`. Store its mapping rows in a `mappings` tab. Boolean values use the lowercase text encoding defined above:

`mapping_id, entity, canonical_field, source_tab, source_column, transform, parameters, required, priority, status`

Example:

| mapping_id | entity | canonical_field | source_tab | source_column | transform | parameters | required | priority | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `bank-csv-v1` | `transactions` | `booked_on` | `Import` | `Date` | `date_iso` | `{"format":"yyyy-MM-dd"}` | `true` | `10` | `active` |
| `bank-csv-v1` | `transactions` | `amount_minor` | `Import` | `Amount` | `money_to_minor` | `{"decimal_separator":"."}` | `true` | `10` | `active` |
| `bank-csv-v1` | `transactions` | `payee` | `Import` | `Merchant` | `trim` | `{}` | `false` | `10` | `active` |

`parameters` is a canonical JSON object whose allowed keys depend on `transform`; it is not executable code. Supported transforms are a closed set: `identity`, `trim`, `date_iso`, `money_to_minor`, `decimal_string`, `account_alias`, and `enum`. `enum` requires `{"map":{"input":"output"}}`. `account_alias` resolves a source account value through `account_aliases` using the import's `source`. `money_to_minor` uses the row currency derived from the resolved account and rejects a source amount with more fractional digits than that currency's `currencies.minor_unit`. Mappings must not execute formulas, scripts, or LLM-generated code.

For one `(mapping_id, entity, canonical_field)`, active rows are evaluated by ascending numeric `priority`; the first row whose source column exists wins for the whole file. Equal active priorities are invalid. The app selects all source columns before parsing rows, then resolves each row's `account_id` through `account_alias`. The row currency is derived from that account before applying any `money_to_minor` transform; an optional mapped currency must equal the account currency or the row is a validation error. A transaction or trade without a valid account or currency cannot be parsed. The selected mapping is then validated for every row; parsing failure never falls through to a lower-priority mapping. An `enum` input missing from its `map` is a row validation error, and the import cannot commit until the user maps, corrects, or excludes that row. This makes the result independent of spreadsheet row order. `mapping_version` versions the complete selected mapping set.

## User-approved LLM migrations

An LLM can inspect sheet headers and redacted sample rows, then propose a versioned migration. It cannot directly edit the tracker.

```text
from_layout_version: 1
to_layout_version: 2
changes:
  - rename_column: transactions.payee → merchant
  - add_column: transactions.project
mapping_updates:
  - canonical.payee ← transactions.merchant
```

Only an application release may change `format_version`. A user-approved layout migration updates `layout_version` and, when mappings change, `mapping_version`.

Before applying a proposal, the app must validate the mapping, preview affected rows, report parsing failures and duplicate risk, and create a backup. The user then explicitly accepts or rejects it.

Removing or changing the type of an ID, account, amount, date, currency, payee, description, or bank source ID requires an explicit data migration. A physical header rename is safe only when its mapping preserves the same canonical value. The app rejects a migration that leaves a required canonical field unmapped or changes fingerprint inputs without recomputing and collision-checking fingerprints.

### Modes

- **Guided schema:** the app offers safe additions and renames, including LLM proposals.
- **Expert custom schema:** the user can change any structure. App and MCP features remain available only for entities with a valid canonical mapping.
