# User interface

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
