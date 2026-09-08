# User interface

## Product experience

The implemented UI contains Dashboard, Transactions, and Assets over synthetic data. The following personal goals and optional family experience is planned; follow the [product delivery order](product.md#delivery-order). Individual users can track finances, goals, and actions without household setup or a member picker.

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
