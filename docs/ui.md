# User interface

## Product experience

The implemented UI contains read-only Dashboard, Transactions, and Assets over a canonical local workbook or synthetic data. Portfolios, widget configuration, mapping setup, personal goals, and the optional family experience below are planned; follow the [product delivery order](product.md#delivery-order). Individual users can track finances, goals, and actions without household setup or a member picker.

The home screen answers three questions:

| Question | Content |
| --- | --- |
| Where do I stand? | Monthly cash flow, recorded cash, data coverage, and upcoming commitments once supported |
| Are my goals on track? | Target, allocated savings, remaining amount, deadline, and required contribution |
| What should I do next? | A short list of explainable actions with a due date; shared actions also show a responsible member |

Use personal wording by default and household wording in a shared view. Provide a reporting period for all users. When family features are enabled, add Household, Mine, and Joint views with a selected member. Label Mine as including that member's joint accounts. Views overlap; do not add their totals or describe filters as privacy controls. Preserve transaction and asset details for inspecting the numbers.

Add a Goals destination when implemented; keep accepted actions with the related goal or on the home screen. Suggestions show evidence, assumptions, and options to accept or dismiss. Accepted actions can be marked done, which does not record a payment or change savings progress.

Display both last refresh time and data-through date. Show missing sources, stale data, invalid records, and unavailable valuations where they affect a report. Withhold affected suggestions. Do not label a balance as available to spend before commitments are supported, or claim continuous monitoring while the app is closed.

Keep budgeting guidance useful without chat. Optional AI explanations use the same approved report scope and visible caveats.

## Investment portfolios

Extend Assets with an All portfolios view, individual portfolio selection, and an explicit Unassigned group. Provide controls to name portfolios and assign investment accounts when persistence is implemented. The initial account-grouping scope and combined-summary rules are defined in [product requirements](product.md#investment-portfolios).

Show investment value, remaining cost, realized and unrealized gains, and holdings; show cash separately and clearly label a cash-plus-investments total. Expose the included accounts, valuation date, reporting currency, and price/FX policy. Retain account detail when the same instrument appears in several accounts. A portfolio summary can also appear as a dashboard widget.

## Widget configuration

Every feature widget exposes its applicable settings through an Edit layout or Configure action. This applies to Dashboard, Transactions, Assets, and future features. Defaults must provide a useful screen without configuration.

| Setting | Behavior |
| --- | --- |
| Visibility and order | Show, hide, and reorder widgets with accessible controls |
| Instance and title | Add multiple instances with distinct titles and scopes |
| Data scope | Select portfolios or accounts using stable IDs; display the active scope |
| Fields and grouping | Choose supported fields, sorting, and grouping for that widget |
| Reporting | Choose supported period, valuation date, and reporting currency; visibly identify overrides of screen defaults |
| Persistence | Restore settings on reopening the tracker; offer reset to defaults |

Hiding a widget does not remove its records from tracker totals. Overlapping widget scopes are views, not values to add together. Removed account or portfolio references produce an actionable configuration error rather than silently broadening a widget to all accounts. Financial rules, required data-quality notices, and accessible labels cannot be disabled through presentation settings.

## Source mapping setup

Let users select the source sheet/table and header row or range, map columns to canonical fields, choose supported conversions and aliases, preview normalized rows, and save a named profile. Show each error with its source location, target field, and correction needed. Mapping a workbook layout is available independently of the later bank-import workflow.

For example, map `Broker activity / Execution date` to `trades.traded_on` once, then configure a Retirement holdings widget and an All portfolios summary over the same validated records. Changing the widget's title or columns does not alter the source mapping.

Explain which widgets become available from the mapped entities and which still need data. Distinguish a mapped table with no records from an unmapped or invalid table. Never display unavailable investments as a zero balance or manufacture trade history from a holdings snapshot.

Source profiles are portable; widget presentation preferences are local to the device and tracker. If a profile is saved locally while the workbook reader remains read-only, state that clearly. A changed source layout requires revalidation and a preview before activating its updated mapping. Preserve the last valid profile if setup is cancelled or validation fails.

## Library choice

Use Flutter's built-in Material 3 widgets as the UI library. Do not add a third-party design system for v1.

Material 3 provides the required forms, cards, dialogs, navigation, theming, accessibility, and responsive building blocks for a finance tracker.

Use Cupertino widgets selectively where an iOS convention materially improves the experience, such as platform-appropriate pickers or action sheets.

## Responsive layout

Use Flutter's built-in `LayoutBuilder`, `MediaQuery`, and `SafeArea`.

- Compact windows use a `NavigationBar`.
- Windows at least 600 logical pixels wide use a `NavigationRail`.
- Larger windows may show transaction lists and their details side by side.

## Deferred dependencies

Do not add a UI kit, state-management framework, or adaptive-scaffold package solely for future flexibility.

Add a chart package such as `fl_chart` only when analytics graphs are implemented. Until then, use accessible totals, tables, and trend text.
