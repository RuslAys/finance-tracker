import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../format.dart';
import '../tracker_controller.dart';

/// A balance is absent only when the document could not be computed at all; a
/// real balance of zero is present and formatted.
String _balanceText(TrackerController controller, Account account) {
  final balance = controller.balances[account.id];
  return balance == null
      ? 'Unavailable'
      : formatMinor(
          balance,
          account.currency,
          controller.minorUnit(account.currency),
        );
}

/// A total is absent when a row of the period had no rate; showing a number
/// then would present a partial month as the whole one.
String _flowText(Minor? amount, String currency, int minorUnit) =>
    amount == null ? 'Unavailable' : formatMinor(amount, currency, minorUnit);

/// Moves the report one month at a time and names the month it shows.
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) {
    final start = controller.periodStart;
    return ListTile(
      leading: IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: () =>
            controller.selectMonth(DateTime.utc(start.year, start.month - 1, 1)),
        tooltip: 'Previous month',
      ),
      title: Text(
        formatIsoDate(start).substring(0, 7),
        textAlign: TextAlign.center,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: () =>
            controller.selectMonth(DateTime.utc(start.year, start.month + 1, 1)),
        tooltip: 'Next month',
      ),
    );
  }
}

/// Net worth, account balances, and cash flow of the open tracker.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final base = controller.baseCurrency;
      final baseUnit = controller.minorUnit(base);
      final netWorth = controller.netWorthMinor;
      final flow = controller.cashFlow;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Net worth'),
              subtitle: Text('Cash and positions in $base'),
              trailing: Text(
                // A missing rate or price makes the total unavailable; showing
                // a number here would hide a position instead of reporting it.
                netWorth == null
                    ? 'Unavailable'
                    : formatMinor(netWorth, base, baseUnit),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          if (controller.financeError != null)
            _MessageCard(
              icon: Icons.error_outline,
              color: theme.colorScheme.error,
              title: 'Results cannot be computed',
              message: controller.financeError!,
            ),
          if (controller.validationErrors.isNotEmpty)
            _MessageCard(
              icon: Icons.warning,
              color: theme.colorScheme.error,
              title:
                  '${controller.validationErrors.length} validation '
                  '${controller.validationErrors.length == 1 ? 'error' : 'errors'}',
              message: controller.validationErrors
                  .take(5)
                  .map((error) => error.toString())
                  .join('\n'),
            ),
          const _SectionHeader('Accounts'),
          for (final account in controller.document.accounts.values)
            ListTile(
              title: Text(account.name),
              subtitle: Text(account.type),
              trailing: Text(_balanceText(controller, account)),
            ),
          if (controller.financeError == null) ...[
            const _SectionHeader('Cash flow'),
            _MonthSelector(controller: controller),
            if (!flow.isComplete)
              _MessageCard(
                icon: Icons.help_outline,
                color: theme.colorScheme.error,
                title: 'Cash flow unavailable for this month',
                message:
                    'No ${controller.rateProvider} rate to $base on the '
                    'booking date of '
                    '${flow.unconvertedCurrencies.join(', ')} records. A '
                    'total without them would understate the month.',
              ),
            ListTile(
              title: const Text('Income'),
              trailing: Text(_flowText(flow.totalIncome, base, baseUnit)),
            ),
            ListTile(
              title: const Text('Expense'),
              trailing: Text(_flowText(flow.totalExpense, base, baseUnit)),
            ),
            ListTile(
              title: Text('Net', style: theme.textTheme.titleMedium),
              trailing: Text(
                _flowText(flow.net, base, baseUnit),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              // Neither line claims the records are complete through today:
              // nothing here fetches from a bank, and no stored field says how
              // far the user's own entry has got.
              'Valued on ${formatIsoDate(controller.asOf)}, computed at '
              '${controller.refreshedAt.toLocal().toString().substring(11, 16)}'
              '.\nSample data. Opening a workbook or Google Sheet is not '
              'implemented yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(message),
    ),
  );
}
