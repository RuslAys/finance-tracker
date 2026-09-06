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
            ListTile(
              title: const Text('Income'),
              trailing: Text(formatMinor(flow.totalIncome, base, baseUnit)),
            ),
            ListTile(
              title: const Text('Expense'),
              trailing: Text(formatMinor(flow.totalExpense, base, baseUnit)),
            ),
            ListTile(
              title: Text('Net', style: theme.textTheme.titleMedium),
              trailing: Text(
                formatMinor(flow.net, base, baseUnit),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text(
              'Sample data. Opening a workbook or Google Sheet is not '
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
