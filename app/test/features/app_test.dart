import 'package:finance_tracker/app.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/features/format.dart';
import 'package:finance_tracker/features/sample_tracker.dart';
import 'package:finance_tracker/features/tracker_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerController _controller() => TrackerController(
  sampleTracker(),
  priceProvider: sampleProvider,
  rateProvider: sampleProvider,
);

void main() {
  test('formats minor units with the currency scale', () {
    expect(formatMinor(123456, 'EUR', 2), '1234.56 EUR');
    expect(formatMinor(-5, 'EUR', 2), '-0.05 EUR');
    expect(formatMinor(1234, 'JPY', 0), '1234 JPY');
    expect(formatMinor(0, 'KWD', 3), '0.000 KWD');
  });

  test('the sample tracker is a valid document', () {
    expect(_controller().validationErrors, isEmpty);
  });

  test('net worth converts the foreign account and values the position', () {
    // 1478.30 + 74.25 EUR cash, 1200.00 USD at 1.08, 3.75 units at 120.10. The
    // broker cash is what the funding transfer left after both buys settled.
    expect(_controller().netWorthMinor, 311404);
  });

  test('the sample does not leave invested cash in the balance', () {
    final controller = _controller();
    final invested = controller.holdings.single.costMinor;
    expect(controller.balances['acc-broker'], 50000 - invested);
  });

  testWidgets('renders balances, then switches to positions', (tester) async {
    final controller = _controller();
    await tester.pumpWidget(FinanceTrackerApp(controller: controller));

    expect(find.text('Net worth'), findsOneWidget);
    expect(find.text('3114.04 EUR'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('1478.30 EUR'), findsOneWidget);

    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.text('VWCE'), findsOneWidget);
    expect(find.text('450.38 EUR'), findsOneWidget);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('-1150.00 EUR'), findsOneWidget);
  });

  testWidgets('reports an invalid document instead of crashing', (
    tester,
  ) async {
    // An amount past the exact minor-unit range throws RangeError inside the
    // engine; the screen must still render the validation report.
    final controller = TrackerController(
      TrackerDocument(
        trackerId: 'broken',
        baseCurrency: 'EUR',
        currencies: const {'EUR': 2},
        accounts: const {
          'acc-1': Account(
            id: 'acc-1',
            name: 'Checking',
            type: 'cash',
            currency: 'EUR',
          ),
        },
        transactions: [
          for (final id in ['t1', 't2'])
            Transaction(
              id: id,
              accountId: 'acc-1',
              bookedOn: parseIsoDate('2026-03-01'),
              amountMinor: 9007199254740991,
              currency: 'EUR',
            ),
        ],
      ),
    );
    expect(controller.financeError, isNotNull);

    await tester.pumpWidget(FinanceTrackerApp(controller: controller));
    expect(find.text('Results cannot be computed'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
  });

  testWidgets('uses a bar on a compact window and a rail on a wide one', (
    tester,
  ) async {
    await tester.pumpWidget(FinanceTrackerApp(controller: _controller()));

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
