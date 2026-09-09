import 'package:finance_tracker/app.dart';
import 'package:finance_tracker/domain/decimal.dart';
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

  test('reports one month at a time and converts on the booking date', () {
    final doc = TrackerDocument(
      trackerId: 'periods',
      baseCurrency: 'EUR',
      currencies: const {'EUR': 2, 'USD': 2},
      accounts: const {
        'acc-1': Account(
          id: 'acc-1',
          name: 'Checking',
          type: 'cash',
          currency: 'EUR',
        ),
        'acc-2': Account(
          id: 'acc-2',
          name: 'USD savings',
          type: 'cash',
          currency: 'USD',
        ),
      },
      transactions: [
        Transaction(
          id: 't1',
          accountId: 'acc-1',
          bookedOn: parseIsoDate('2026-02-10'),
          amountMinor: -5000,
          currency: 'EUR',
        ),
        Transaction(
          id: 't2',
          accountId: 'acc-2',
          bookedOn: parseIsoDate('2026-03-10'),
          amountMinor: 12000,
          currency: 'USD',
        ),
      ],
      fxRates: [
        FxRate(
          baseCurrency: 'EUR',
          quoteCurrency: 'USD',
          pricedOn: parseIsoDate('2026-03-01'),
          rate: Decimal.parse('1.2'),
          provider: 'demo',
        ),
      ],
    );
    final controller = TrackerController(
      doc,
      asOf: parseIsoDate('2026-03-31'),
      period: parseIsoDate('2026-03-15'),
    );
    expect(controller.periodStart, parseIsoDate('2026-03-01'));
    expect(controller.periodEnd, parseIsoDate('2026-03-31'));
    // 120.00 USD at 1.2 is 100.00 EUR: the March row counts, February's does not.
    expect(controller.cashFlow.net, 10000);

    controller.selectMonth(parseIsoDate('2026-02-10'));
    expect(controller.periodEnd, parseIsoDate('2026-02-28'));
    expect(controller.cashFlow.net, -5000);
  });

  testWidgets('renders balances, then switches to positions', (tester) async {
    final controller = _controller();
    await tester.pumpWidget(FinanceTrackerApp(controller: controller));

    expect(find.text('Net worth'), findsOneWidget);
    expect(find.text('3114.04 EUR'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('1478.30 EUR'), findsOneWidget);

    // The reported month is named on screen and steps back one month.
    final month = formatIsoDate(controller.periodStart).substring(0, 7);
    expect(find.text(month), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(month), findsNothing);
    expect(
      find.text(formatIsoDate(controller.periodStart).substring(0, 7)),
      findsOneWidget,
    );

    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.text('VWCE'), findsOneWidget);
    // Once on the position, once as the All portfolios summary of that one
    // position.
    expect(find.text('450.38 EUR'), findsNWidgets(2));
    expect(find.text('All portfolios'), findsWidgets);

    // Selecting the empty Unassigned group reports no positions rather than
    // falling back to every account.
    await tester.tap(find.byType(DropdownButtonFormField<({String? id})>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned').last);
    await tester.pumpAndSettle();
    expect(find.text('VWCE'), findsNothing);
    expect(find.text('No positions yet.'), findsOneWidget);
    expect(find.text('Accounts: US broker'), findsOneWidget);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('-1150.00 EUR'), findsOneWidget);
  });

  test('a valid portfolio still reports while the tracker total cannot', () {
    const broker = Account(
      id: 'acc-a',
      name: 'Broker A',
      type: 'brokerage',
      currency: 'EUR',
      portfolioId: 'pf-1',
    );
    final controller = TrackerController(
      TrackerDocument(
        trackerId: 'oversold',
        baseCurrency: 'EUR',
        currencies: const {'EUR': 2},
        accounts: const {
          'acc-a': broker,
          'acc-b': Account(
            id: 'acc-b',
            name: 'Broker B',
            type: 'brokerage',
            currency: 'EUR',
            portfolioId: 'pf-2',
          ),
        },
        portfolios: const {
          'pf-1': Portfolio(id: 'pf-1', name: 'Sound'),
          'pf-2': Portfolio(id: 'pf-2', name: 'Oversold'),
        },
        instruments: const {
          'ins-1': Instrument(
            id: 'ins-1',
            symbol: 'VWCE',
            name: 'World ETF',
            type: 'etf',
            currency: 'EUR',
          ),
        },
        transactions: [
          Transaction(
            id: 't1',
            accountId: 'acc-a',
            bookedOn: parseIsoDate('2026-03-01'),
            amountMinor: 30000,
            currency: 'EUR',
          ),
          Transaction(
            id: 't2',
            accountId: 'acc-a',
            bookedOn: parseIsoDate('2026-03-01'),
            amountMinor: -20000,
            currency: 'EUR',
            tradeId: 'tr1',
          ),
          Transaction(
            id: 't3',
            accountId: 'acc-b',
            bookedOn: parseIsoDate('2026-03-02'),
            amountMinor: 55000,
            currency: 'EUR',
            tradeId: 'tr2',
          ),
        ],
        trades: [
          Trade(
            id: 'tr1',
            accountId: 'acc-a',
            instrumentId: 'ins-1',
            tradedOn: parseIsoDate('2026-03-01'),
            side: TradeSide.buy,
            units: Decimal.parse('2'),
            priceMinor: 10000,
            currency: 'EUR',
          ),
          // Sold out of an empty book: this account has no computable position.
          Trade(
            id: 'tr2',
            accountId: 'acc-b',
            instrumentId: 'ins-1',
            tradedOn: parseIsoDate('2026-03-02'),
            side: TradeSide.sell,
            units: Decimal.parse('10'),
            priceMinor: 5500,
            currency: 'EUR',
          ),
        ],
        prices: [
          Price(
            instrumentId: 'ins-1',
            pricedOn: parseIsoDate('2026-03-01'),
            priceMinor: 11000,
            currency: 'EUR',
            provider: 'demo',
          ),
        ],
      ),
      asOf: parseIsoDate('2026-03-31'),
    );

    // The tracker-wide numbers are gone, and All portfolios includes the broken
    // account, so it withholds too.
    expect(controller.financeError, contains('sells more units'));
    expect(controller.netWorthMinor, isNull);
    expect(controller.portfolioReport.totalMinor, isNull);

    // The sound portfolio reads only its own account and still reports.
    controller.selectPortfolio('pf-1');
    expect(controller.portfolioReport.totalMinor, 32000);
    expect(controller.portfolioReport.unavailable, isEmpty);
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
