import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../format.dart';
import '../tracker_controller.dart';

/// Every transaction a calculation counts, newest first.
///
/// Rows staged by an import that has not committed are absent here for the same
/// reason they are absent from a balance.
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key, required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final transactions = controller.transactions;
      if (transactions.isEmpty) {
        return const Center(child: Text('No transactions yet.'));
      }
      return ListView.separated(
        itemCount: transactions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _TransactionTile(controller: controller, row: transactions[index]),
      );
    },
  );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.controller, required this.row});

  final TrackerController controller;
  final Transaction row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = row.payee.isNotEmpty
        ? row.payee
        : row.description.isNotEmpty
        ? row.description
        : controller.categoryName(row.categoryKey);

    return ListTile(
      title: Text(title),
      subtitle: Text(
        '${formatIsoDate(row.bookedOn)} · '
        '${controller.accountName(row.accountId)} · '
        '${controller.categoryName(row.categoryKey)}',
      ),
      trailing: Text(
        formatMinor(
          row.amountMinor,
          row.currency,
          controller.minorUnit(row.currency),
        ),
        style: theme.textTheme.bodyLarge?.copyWith(
          color: row.amountMinor < 0
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
      ),
    );
  }
}
