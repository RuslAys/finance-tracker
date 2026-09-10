import 'dart:convert';

import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/finance.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/snapshot.dart';
import 'package:finance_tracker/features/sample_tracker.dart';
import 'package:finance_tracker/features/tracker_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = todayUtc();
  final from = today.subtract(const Duration(days: 90));

  FinanceSnapshot snapshotOf({Iterable<String>? accountIds, String? label}) =>
      buildSnapshot(
        sampleTracker(),
        asOf: today,
        periodStart: from,
        periodEnd: today,
        accountIds: accountIds,
        scopeLabel: label ?? 'All accounts',
        priceProvider: sampleProvider,
        rateProvider: sampleProvider,
      );

  test('states the totals the engine computed, and nothing it did not', () {
    final snapshot = snapshotOf();
    final doc = sampleTracker();

    expect(snapshot.trackerId, 'sample');
    expect(snapshot.baseCurrency, 'EUR');
    expect(snapshot.asOf, today);
    expect(snapshot.minorUnits, {'EUR': 2, 'USD': 2});

    // The same number the engine reports, not a second calculation of it.
    expect(
      snapshot.netWorthMinor,
      FinanceEngine.netWorth(
        doc,
        priceProvider: sampleProvider,
        rateProvider: sampleProvider,
        asOf: today,
      ),
    );
    expect(snapshot.isComplete, isTrue);

    // A refund reduces its category rather than becoming income of its own.
    final groceries =
        snapshot.expense!.singleWhere((e) => e.name == 'Groceries');
    expect(groceries.amountMinor, 7170);
    // Transfers and trade settlements move money without spending it, so
    // neither reaches a category.
    expect(snapshot.expense!.map((e) => e.name), isNot(contains('Transfer')));
    expect(snapshot.totalExpenseMinor, 122170);

    final position = snapshot.positions!.single;
    expect(position.symbol, 'VWCE');
    expect(position.units, '3.75');
    expect(position.currency, 'EUR');
    // 3.75 units at 120.10, rounded once.
    expect(position.valueMinor, 45038);
  });

  test('a scoped snapshot counts, names, and values only its accounts', () {
    final snapshot = snapshotOf(
      accountIds: const {'acc-broker'},
      label: 'Retirement',
    );

    expect(snapshot.accounts.map((a) => a.ref), ['brokerage EUR 1']);
    // The broker account holds a transfer leg and two trade settlements, none
    // of which is income or expense: a scope with no flow reports no flow
    // rather than the tracker's.
    expect(snapshot.income, isEmpty);
    expect(snapshot.expense, isEmpty);
    // The position is reported beside the balance it sits next to, under the
    // pseudonym of this snapshot rather than the account it belongs to.
    expect(snapshot.positions!.single.accountRef, 'brokerage EUR 1');

    // Net worth is a property of the whole tracker. Reporting one scope's total
    // under that name would state the user is worth what these accounts hold.
    expect(snapshot.netWorthMinor, isNull);
    expect(snapshot.isComplete, isFalse);
    expect(snapshot.incomplete, contains(contains('Retirement')));
  });

  test('carries no transaction detail out of the tracker', () {
    // What may leave the app is totals, periods, categories, and holdings. A
    // payee, a description, or a row identity is the raw record, and this is
    // the boundary that decides it never reaches a provider or an MCP tool.
    final json = jsonEncode(snapshotOf().toJson());

    for (final secret in const [
      'Employer',
      'Landlord',
      'Supermarket',
      'Freelance client',
      'Returned item',
      'tx-1',
      'trf-1',
      'trd-1',
      // An account name can name the bank, the employer, or the family member
      // behind it, and its id is row identity.
      'Checking',
      'USD savings',
      'acc-broker',
      'cat-groceries',
      'ins-etf',
    ]) {
      expect(json, isNot(contains(secret)), reason: '$secret must not be sent');
    }

    // The report itself is still there: this is a scope boundary, not an empty
    // snapshot that would pass the check by saying nothing.
    expect(json, contains('"net_worth_minor":'));
    expect(json, contains('Groceries'));
    expect(json, contains('VWCE'));
  });

  test('counts broken rows of its own scope, and never of another', () {
    // Two broken transactions: one in the reported account, one in an account
    // the scope excludes. How many rows fail in an account the caller was not
    // approved for is a fact about that account, so it is not counted either.
    final doc = TrackerDocument(
      trackerId: 'trk-broken',
      baseCurrency: 'EUR',
      currencies: const {'EUR': 2},
      accounts: const {
        'acc-reported': Account(
          id: 'acc-reported',
          name: 'Everyday',
          type: 'cash',
          currency: 'EUR',
        ),
        'acc-private': Account(
          id: 'acc-private',
          name: 'Private savings',
          type: 'cash',
          currency: 'EUR',
        ),
      },
      transactions: [
        Transaction(
          id: 'tx-mine',
          accountId: 'acc-reported',
          bookedOn: today,
          amountMinor: 100,
          currency: 'EUR',
          categoryId: 'cat-missing',
        ),
        Transaction(
          id: 'tx-theirs',
          accountId: 'acc-private',
          bookedOn: today,
          amountMinor: 100,
          currency: 'EUR',
          categoryId: 'cat-missing',
        ),
      ],
    );

    final scoped = buildSnapshot(
      doc,
      asOf: today,
      periodStart: from,
      periodEnd: today,
      accountIds: const {'acc-reported'},
      scopeLabel: 'Everyday',
    );

    // One, not two: the excluded account's broken row is not this caller's to
    // know about.
    expect(scoped.incomplete, contains('1 transactions row fails validation'));
    // The whole tracker reports both, because then nothing is excluded.
    final whole = buildSnapshot(
      doc,
      asOf: today,
      periodStart: from,
      periodEnd: today,
    );
    expect(whole.incomplete, contains('2 transactions rows fail validation'));

    final json = jsonEncode(scoped.toJson());
    expect(json, isNot(contains('tx-mine')));
    expect(json, isNot(contains('tx-theirs')));
    expect(json, isNot(contains('acc-private')));
    expect(json, isNot(contains('Private savings')));
    expect(json, isNot(contains('cat-missing')));
  });

  test('books that cannot be replayed are unavailable, not an empty list', () {
    // A sell with no lots behind it: the FIFO books cannot be replayed, and
    // reporting no positions would state the account holds nothing.
    final doc = TrackerDocument(
      trackerId: 'trk-sell',
      baseCurrency: 'EUR',
      currencies: const {'EUR': 2},
      accounts: const {
        'acc-1': Account(
          id: 'acc-1',
          name: 'Broker',
          type: 'brokerage',
          currency: 'EUR',
        ),
      },
      instruments: const {
        'ins-1': Instrument(
          id: 'ins-1',
          symbol: 'ACME',
          name: 'Acme',
          type: 'stock',
          currency: 'EUR',
        ),
      },
      trades: [
        Trade(
          id: 'trd-1',
          accountId: 'acc-1',
          instrumentId: 'ins-1',
          tradedOn: today,
          side: TradeSide.sell,
          units: Decimal.parse('5'),
          priceMinor: 100,
          currency: 'EUR',
        ),
      ],
    );

    final snapshot = buildSnapshot(
      doc,
      asOf: today,
      periodStart: from,
      periodEnd: today,
    );

    expect(snapshot.positions, isNull);
    expect(
      snapshot.incomplete,
      contains(contains('Holdings are unavailable')),
    );
    expect(jsonEncode(snapshot.toJson()), contains('"positions":null'));
  });

  test('a position too valuable to state exactly does not take the rest', () {
    // Cost is exactly representable while units times the current price is not.
    final doc = TrackerDocument(
      trackerId: 'trk-huge',
      baseCurrency: 'EUR',
      currencies: const {'EUR': 2},
      accounts: const {
        'acc-1': Account(
          id: 'acc-1',
          name: 'Broker',
          type: 'brokerage',
          currency: 'EUR',
        ),
      },
      instruments: const {
        'ins-1': Instrument(
          id: 'ins-1',
          symbol: 'ACME',
          name: 'Acme',
          type: 'stock',
          currency: 'EUR',
        ),
      },
      transactions: [
        Transaction(
          id: 'tx-settle',
          accountId: 'acc-1',
          bookedOn: today,
          amountMinor: -10000000000,
          currency: 'EUR',
          tradeId: 'trd-1',
        ),
      ],
      trades: [
        Trade(
          id: 'trd-1',
          accountId: 'acc-1',
          instrumentId: 'ins-1',
          tradedOn: today,
          side: TradeSide.buy,
          units: Decimal.parse('10000000000'),
          priceMinor: 1,
          currency: 'EUR',
        ),
      ],
      prices: [
        Price(
          instrumentId: 'ins-1',
          pricedOn: today,
          priceMinor: 1000000,
          currency: 'EUR',
          provider: 'demo',
        ),
      ],
    );

    final snapshot = buildSnapshot(
      doc,
      asOf: today,
      periodStart: from,
      periodEnd: today,
    );

    // The position is still reported, with its cost, and only its value is
    // withheld — with a reason that says why, not that no price exists.
    final position = snapshot.positions!.single;
    expect(position.costMinor, 10000000000);
    expect(position.valueMinor, isNull);
    expect(
      snapshot.incomplete,
      contains('The value of ACME is outside the exact minor-unit range'),
    );
    expect(jsonEncode(snapshot.toJson()), contains('"value_minor":null'));
  });

  test('reports an uncomputable balance as unavailable, never as zero', () {
    // Two exact amounts whose sum this platform cannot hold: the balance is
    // unknown, and a zero would read as an account that holds nothing.
    final maxMinor = 9007199254740991;
    final doc = TrackerDocument(
      trackerId: 'trk-overflow',
      baseCurrency: 'EUR',
      currencies: const {'EUR': 2},
      accounts: const {
        'acc-1': Account(
          id: 'acc-1',
          name: 'Everyday',
          type: 'cash',
          currency: 'EUR',
        ),
      },
      transactions: [
        for (final id in const ['tx-1', 'tx-2'])
          Transaction(
            id: id,
            accountId: 'acc-1',
            bookedOn: today,
            amountMinor: maxMinor,
            currency: 'EUR',
          ),
      ],
    );

    final snapshot = buildSnapshot(
      doc,
      asOf: today,
      periodStart: from,
      periodEnd: today,
    );

    expect(snapshot.accounts.single.balanceMinor, isNull);
    // The period is unavailable rather than a month in which nothing happened.
    expect(snapshot.income, isNull);
    expect(snapshot.expense, isNull);
    expect(snapshot.totalIncomeMinor, isNull);
    expect(snapshot.netWorthMinor, isNull);
    expect(
      snapshot.incomplete,
      contains(contains('Account balances are unavailable')),
    );

    final json = jsonEncode(snapshot.toJson());
    expect(json, contains('"balance_minor":null'));
    expect(json, contains('"income":null'));
  });

  test('says why a holding has no value, and withholds a net it cannot hold', () {
    // One unpriced position, and a period whose two sides are each exactly
    // representable while their difference is not.
    final maxMinor = 9007199254740991;
    final doc = TrackerDocument(
      trackerId: 'trk-edges',
      baseCurrency: 'EUR',
      currencies: const {'EUR': 2},
      accounts: const {
        'acc-1': Account(
          id: 'acc-1',
          name: 'Salary account',
          type: 'cash',
          currency: 'EUR',
        ),
        'acc-2': Account(
          id: 'acc-2',
          name: 'Broker',
          type: 'brokerage',
          currency: 'EUR',
        ),
      },
      categories: const {
        'cat-in': Category(id: 'cat-in', name: 'In', type: CategoryType.income),
        'cat-out': Category(
          id: 'cat-out',
          name: 'Out',
          type: CategoryType.expense,
        ),
      },
      instruments: const {
        'ins-1': Instrument(
          id: 'ins-1',
          symbol: 'ACME',
          name: 'Acme',
          type: 'stock',
          currency: 'EUR',
        ),
      },
      transactions: [
        Transaction(
          id: 'tx-in',
          accountId: 'acc-1',
          bookedOn: today,
          amountMinor: maxMinor,
          currency: 'EUR',
          categoryId: 'cat-in',
        ),
        // A refund larger than anything spent: the expense side of the period
        // is a negative total, which is why the two sides can be that far apart.
        Transaction(
          id: 'tx-out',
          accountId: 'acc-2',
          bookedOn: today,
          amountMinor: maxMinor,
          currency: 'EUR',
          categoryId: 'cat-out',
        ),
        Transaction(
          id: 'tx-settle',
          accountId: 'acc-2',
          bookedOn: today,
          amountMinor: -1000,
          currency: 'EUR',
          tradeId: 'trd-1',
        ),
      ],
      trades: [
        Trade(
          id: 'trd-1',
          accountId: 'acc-2',
          instrumentId: 'ins-1',
          tradedOn: today,
          side: TradeSide.buy,
          units: Decimal.parse('10'),
          priceMinor: 100,
          currency: 'EUR',
        ),
      ],
    );

    final snapshot = buildSnapshot(
      doc,
      asOf: today,
      periodStart: from,
      periodEnd: today,
    );

    // Each side is a real total; their difference is not, so it is unavailable
    // rather than a rounded number that reads as real.
    expect(snapshot.totalIncomeMinor, maxMinor);
    expect(snapshot.totalExpenseMinor, -maxMinor);
    expect(snapshot.netMinor, isNull);
    expect(
      snapshot.incomplete,
      contains(contains('outside the exact minor-unit range')),
    );
    // Serializing must not be where that limit is discovered.
    expect(() => jsonEncode(snapshot.toJson()), returnsNormally);

    // Nothing else would report the missing price: this snapshot has no net
    // worth to withhold either.
    expect(snapshot.positions!.single.valueMinor, isNull);
    expect(snapshot.incomplete, contains(contains('No price or rate for ACME')));
  });
}
