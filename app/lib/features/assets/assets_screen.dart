import 'package:flutter/material.dart';

import '../../domain/decimal.dart';
import '../../domain/finance.dart';
import '../../domain/models.dart';
import '../format.dart';
import '../tracker_controller.dart';

/// Investments by portfolio: a summary of the selected scope, then the FIFO
/// positions it contains with their cost, market value, and realized result.
class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final error = controller.financeError;
      final groups = controller.portfolioGroups;
      // A failure elsewhere in the tracker leaves the tracker-wide totals
      // unavailable, but each portfolio is computed from its own accounts, so
      // the selected one is still worth showing.
      if (error != null && groups.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error, textAlign: TextAlign.center),
          ),
        );
      }
      // Without an investment account there is nothing to group, so the screen
      // stays the plain position list it was.
      final holdings = groups.isEmpty
          ? controller.holdings
          : controller.portfolioReport.holdings;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (groups.isNotEmpty) ...[
            _PortfolioPicker(controller: controller),
            const SizedBox(height: 8),
            _SummaryCard(controller: controller),
          ],
          if (holdings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No positions yet.')),
            ),
          for (final holding in holdings)
            _HoldingCard(controller: controller, holding: holding),
        ],
      );
    },
  );
}

/// All portfolios, one named portfolio, or the explicit Unassigned group.
class _PortfolioPicker extends StatelessWidget {
  const _PortfolioPicker({required this.controller});

  final TrackerController controller;

  @override
  // A record, not a bare id: a string sentinel for All portfolios would be a
  // real id a tracker is free to use, and the two entries would then collide.
  // The absent id is All portfolios; the empty id is the Unassigned group.
  Widget build(BuildContext context) => DropdownButtonFormField<({String? id})>(
    initialValue: (id: controller.portfolioId),
    decoration: const InputDecoration(
      labelText: 'Portfolio',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem(value: (id: null), child: Text('All portfolios')),
      for (final group in controller.portfolioGroups)
        DropdownMenuItem(value: (id: group.id), child: Text(group.name)),
    ],
    onChanged: (value) => controller.selectPortfolio(value?.id),
  );
}

/// The selected scope's totals, with cash kept apart from positions.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) {
    final report = controller.portfolioReport;
    final currency = report.currency;
    final unit = controller.minorUnit(currency);
    final theme = Theme.of(context);

    // An unavailable total is never rendered as zero; the reasons below say why.
    String money(Minor? amount) =>
        amount == null ? 'Unavailable' : formatMinor(amount, currency, unit);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.portfolioId == null
                  ? 'All portfolios'
                  : controller.portfolioGroups
                        .firstWhere((g) => g.id == controller.portfolioId)
                        .name,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              'Valued ${formatIsoDate(controller.asOf)} in $currency · prices '
              '${controller.priceProvider} · rates ${controller.rateProvider}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _Row('Investments', money(report.valueMinor)),
            _Row('Cost', money(report.costMinor)),
            _Row('Unrealized', money(report.unrealizedGainMinor)),
            _Row('Realized', money(report.realizedGainMinor)),
            _Row('Account cash', money(report.cashMinor)),
            _Row('Cash + investments', money(report.totalMinor)),
            const SizedBox(height: 8),
            Text(
              report.accountIds.isEmpty
                  ? 'No accounts in this portfolio'
                  : 'Accounts: '
                        '${report.accountIds.map(controller.accountName).join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            for (final reason in report.unavailable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({required this.controller, required this.holding});

  final TrackerController controller;
  final Holding holding;

  @override
  Widget build(BuildContext context) {
    final unit = controller.minorUnit(holding.currency);
    final value = controller.marketValue(holding);
    String money(int amount) => formatMinor(amount, holding.currency, unit);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.instrumentName(holding.instrumentId),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            // Kept per account: the same instrument in two accounts has two
            // FIFO books, and merging them would change the cost of both.
            Text(controller.accountName(holding.accountId)),
            const SizedBox(height: 8),
            _Row('Units', holding.units.toString()),
            _Row('Cost', money(holding.costMinor)),
            // An unpriced position has no value; it is not worth zero.
            _Row('Value', value == null ? 'Unavailable' : money(value)),
            _Row(
              'Unrealized',
              value == null
                  ? 'Unavailable'
                  : money(subtractMinor(value, holding.costMinor)),
            ),
            _Row('Realized', money(holding.realizedGainMinor)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value)],
    ),
  );
}
