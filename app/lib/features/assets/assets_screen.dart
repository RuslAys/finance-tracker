import 'package:flutter/material.dart';

import '../../domain/decimal.dart';
import '../../domain/finance.dart';
import '../format.dart';
import '../tracker_controller.dart';

/// FIFO positions with their cost, market value, and realized result.
class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, required this.controller});

  final TrackerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final error = controller.financeError;
      if (error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error, textAlign: TextAlign.center),
          ),
        );
      }
      final holdings = controller.holdings;
      if (holdings.isEmpty) {
        return const Center(child: Text('No positions yet.'));
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final holding in holdings)
            _HoldingCard(controller: controller, holding: holding),
        ],
      );
    },
  );
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
