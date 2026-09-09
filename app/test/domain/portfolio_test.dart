import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/finance.dart';
import 'package:finance_tracker/domain/fx.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two named portfolios, one unassigned investment account, and a cash account
/// that must never appear in an investment report.
///
/// `acc-eur` holds 2 units bought at 100.00 and 100.00 of cash left over;
/// `acc-alt` holds 1 unit bought at 50.00 and 50.00 left over. Each buy settles
/// as its own cash row, exactly as the format requires.
TrackerDocument _doc({bool foreignTrade = false}) => TrackerDocument(
  trackerId: 'trk-1',
  baseCurrency: 'EUR',
  currencies: const {'EUR': 2, 'USD': 2},
  accounts: const {
    'acc-cash': Account(
      id: 'acc-cash',
      name: 'Checking',
      type: 'cash',
      currency: 'EUR',
    ),
    'acc-eur': Account(
      id: 'acc-eur',
      name: 'Broker EUR',
      type: 'brokerage',
      currency: 'EUR',
      portfolioId: 'pf-1',
    ),
    'acc-alt': Account(
      id: 'acc-alt',
      name: 'Broker alt',
      type: 'brokerage',
      currency: 'EUR',
      portfolioId: 'pf-2',
    ),
    'acc-usd': Account(
      id: 'acc-usd',
      name: 'Broker USD',
      type: 'brokerage',
      currency: 'USD',
    ),
  },
  portfolios: const {
    'pf-1': Portfolio(id: 'pf-1', name: 'Retirement'),
    'pf-2': Portfolio(id: 'pf-2', name: 'Aggressive'),
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
    _tx('t1', 30000, 'acc-eur'),
    _tx('t2', -20000, 'acc-eur', tradeId: 'tr1'),
    _tx('t3', 10000, 'acc-alt'),
    _tx('t4', -5000, 'acc-alt', tradeId: 'tr2'),
    if (foreignTrade) ...[
      _tx('t5', 50000, 'acc-usd', currency: 'USD'),
      _tx('t6', -10000, 'acc-usd', currency: 'USD', tradeId: 'tr3'),
    ],
  ],
  trades: [
    _trade('tr1', 'acc-eur', '2', 10000),
    _trade('tr2', 'acc-alt', '1', 5000),
    if (foreignTrade) _trade('tr3', 'acc-usd', '1', 10000, currency: 'USD'),
  ],
  prices: [
    _price(11000, 'EUR'),
    if (foreignTrade) _price(11000, 'USD'),
  ],
  fxRates: [
    FxRate(
      baseCurrency: 'EUR',
      quoteCurrency: 'USD',
      pricedOn: parseIsoDate('2026-03-01'),
      rate: Decimal.parse('1.1'),
      provider: 'ecb',
    ),
  ],
);

Transaction _tx(
  String id,
  int amountMinor,
  String accountId, {
  String? tradeId,
  String currency = 'EUR',
  String bookedOn = '2026-03-01',
}) => Transaction(
  id: id,
  accountId: accountId,
  bookedOn: parseIsoDate(bookedOn),
  amountMinor: amountMinor,
  currency: currency,
  tradeId: tradeId,
);

Trade _trade(
  String id,
  String accountId,
  String units,
  int priceMinor, {
  String currency = 'EUR',
}) => Trade(
  id: id,
  accountId: accountId,
  instrumentId: 'ins-1',
  tradedOn: parseIsoDate('2026-03-01'),
  side: TradeSide.buy,
  units: Decimal.parse(units),
  priceMinor: priceMinor,
  currency: currency,
);

Transaction _transferLeg(
  String id,
  int amountMinor,
  String accountId,
  String bookedOn,
) => Transaction(
  id: id,
  accountId: accountId,
  bookedOn: parseIsoDate(bookedOn),
  amountMinor: amountMinor,
  currency: 'EUR',
  categoryId: 'cat-1',
  transferId: 'trf-1',
);

Price _price(int priceMinor, String currency) => Price(
  instrumentId: 'ins-1',
  pricedOn: parseIsoDate('2026-03-01'),
  priceMinor: priceMinor,
  currency: currency,
  provider: 'stooq',
);

PortfolioReport _report(
  TrackerDocument doc,
  Iterable<String> accountIds, {
  String asOf = '2026-03-31',
}) => FinanceEngine.portfolioReport(
  doc,
  accountIds: accountIds,
  currency: 'EUR',
  priceProvider: 'stooq',
  rateProvider: 'ecb',
  asOf: parseIsoDate(asOf),
);

List<String> _scope(List<PortfolioGroup> groups) => [
  for (final group in groups) ...group.accountIds,
];

void main() {
  group('portfolioGroups', () {
    test('lists named portfolios by name, then Unassigned', () {
      final groups = FinanceEngine.portfolioGroups(_doc());
      expect(groups.map((g) => g.name), ['Aggressive', 'Retirement', 'Unassigned']);
      expect(groups.last.isUnassigned, isTrue);
      expect(groups.map((g) => g.accountIds), [
        ['acc-alt'],
        ['acc-eur'],
        ['acc-usd'],
      ]);
    });

    test('leaves cash accounts out of every group', () {
      final grouped = _scope(FinanceEngine.portfolioGroups(_doc()));
      expect(grouped, isNot(contains('acc-cash')));
    });

    test('an account belongs to at most one group', () {
      final grouped = _scope(FinanceEngine.portfolioGroups(_doc()));
      expect(grouped.toSet().length, grouped.length);
    });
  });

  group('portfolioReport', () {
    test('reports one portfolio without the other', () {
      final report = _report(_doc(), const ['acc-eur']);
      expect(report.holdings.single.accountId, 'acc-eur');
      expect(report.valueMinor, 22000);
      expect(report.costMinor, 20000);
      expect(report.unrealizedGainMinor, 2000);
      expect(report.realizedGainMinor, 0);
      expect(report.cashMinor, 10000);
      expect(report.totalMinor, 32000);
      expect(report.unavailable, isEmpty);
    });

    test('the combined summary counts each account once', () {
      final doc = _doc();
      final all = _report(doc, _scope(FinanceEngine.portfolioGroups(doc)));
      // 3 units at 110.00, 150.00 of cash across the three accounts. Adding the
      // two portfolio reports would double nothing here; repeating an account
      // in the scope must not double it either.
      expect(all.accountIds, ['acc-alt', 'acc-eur', 'acc-usd']);
      expect(all.valueMinor, 33000);
      expect(all.costMinor, 25000);
      expect(all.cashMinor, 15000);
      expect(all.totalMinor, 48000);

      final repeated = _report(doc, const [
        'acc-eur',
        'acc-eur',
        'acc-alt',
        'acc-usd',
      ]);
      expect(repeated.valueMinor, all.valueMinor);
      expect(repeated.cashMinor, all.cashMinor);
    });

    test('an unpriced position makes the value unavailable, not zero', () {
      final doc = _doc();
      final unpriced = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        fxRates: doc.fxRates,
      );
      final report = _report(unpriced, const ['acc-eur']);
      expect(report.valueMinor, isNull);
      expect(report.unrealizedGainMinor, isNull);
      expect(report.totalMinor, isNull);
      // Cost and cash are still known; only the priced totals are missing.
      expect(report.costMinor, 20000);
      expect(report.cashMinor, 10000);
      expect(report.unavailable.single, contains('No price for ins-1'));
    });

    test('withholds cost across currencies but still values the position', () {
      final report = _report(_doc(foreignTrade: true), const ['acc-usd']);
      // 1 unit at 110.00 USD and 400.00 USD of cash, both at 1.1 to EUR.
      expect(report.valueMinor, 10000);
      expect(report.cashMinor, 36364);
      expect(report.costMinor, isNull);
      expect(report.realizedGainMinor, isNull);
      expect(report.unrealizedGainMinor, isNull);
      expect(report.unavailable.single, contains('historical conversion'));
    });

    test('is unavailable when a settlement disagrees with its trade', () {
      final doc = _doc();
      final wrong = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        // Both rows exist and are dated in March, so the id-and-date check
        // passes; the cash that left is not what the trade cost.
        transactions: [
          for (final t in doc.transactions)
            if (t.id != 't2') t else _tx('t2', -19000, 'acc-eur', tradeId: 'tr1'),
        ],
        trades: doc.trades,
        prices: doc.prices,
        fxRates: doc.fxRates,
      );
      final report = _report(wrong, const ['acc-eur']);
      expect(report.valueMinor, isNull);
      expect(report.cashMinor, isNull);
      expect(report.costMinor, isNull);
      expect(report.unavailable.single, contains('Settlement amount'));

      // The other portfolio's records are intact, so its report still stands.
      expect(_report(wrong, const ['acc-alt']).totalMinor, 16000);
    });

    test('values a fully sold position at zero without a current price', () {
      final doc = _doc();
      final sold = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: [
          ...doc.transactions,
          _tx('t7', 22000, 'acc-eur', tradeId: 'tr4'),
        ],
        trades: [
          ...doc.trades,
          Trade(
            id: 'tr4',
            accountId: 'acc-eur',
            instrumentId: 'ins-1',
            tradedOn: parseIsoDate('2026-03-10'),
            side: TradeSide.sell,
            units: Decimal.parse('2'),
            priceMinor: 11000,
            currency: 'EUR',
          ),
        ],
        // No prices at all: the book is empty, so none is needed.
        fxRates: doc.fxRates,
      );
      final report = _report(sold, const ['acc-eur']);
      expect(report.holdings.single.units, Decimal.zero);
      expect(report.valueMinor, 0);
      expect(report.realizedGainMinor, 2000);
      expect(report.cashMinor, 32000);
      expect(report.unavailable, isEmpty);

      // Nor does a rejected price for the sold instrument matter: the closed
      // book never reads one.
      final rejected = TrackerDocument(
        trackerId: sold.trackerId,
        baseCurrency: sold.baseCurrency,
        currencies: sold.currencies,
        accounts: sold.accounts,
        portfolios: sold.portfolios,
        instruments: sold.instruments,
        transactions: sold.transactions,
        trades: sold.trades,
        prices: [
          Price(
            instrumentId: 'ins-1',
            pricedOn: parseIsoDate('2026-03-20'),
            priceMinor: -500,
            currency: 'EUR',
            provider: 'stooq',
          ),
        ],
        fxRates: sold.fxRates,
      );
      expect(_report(rejected, const ['acc-eur']).totalMinor, 32000);
    });

    test('an empty foreign account needs no rate', () {
      // acc-usd holds nothing and no EUR/USD observation exists on this date.
      final doc = _doc();
      final noRate = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        prices: doc.prices,
      );
      final report = _report(noRate, const ['acc-usd']);
      expect(report.cashMinor, 0);
      expect(report.totalMinor, 0);
      expect(report.unavailable, isEmpty);
    });

    test('never values a position from a rejected price row', () {
      final doc = _doc();
      final negative = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        prices: [
          _price(11000, 'EUR'),
          Price(
            instrumentId: 'ins-1',
            pricedOn: parseIsoDate('2026-03-20'),
            priceMinor: -500,
            currency: 'EUR',
            provider: 'stooq',
          ),
        ],
        fxRates: doc.fxRates,
      );
      final holding = FinanceEngine.holdings(
        negative,
      ).firstWhere((h) => h.accountId == 'acc-eur');
      // The later row is rejected, so the last valid observation values it: a
      // negative price must never become a negative position.
      expect(
        FinanceEngine.marketValue(
          negative,
          holding,
          provider: 'stooq',
          asOf: parseIsoDate('2026-03-31'),
        )?.amount,
        22000,
      );
      // The report still withholds its totals, and says which row is broken.
      final report = _report(negative, const ['acc-eur']);
      expect(report.valueMinor, isNull);
      expect(report.unavailable.single, contains('price_minor'));
    });

    test('a rejected rate is not an observation', () {
      final doc = _doc(foreignTrade: true);
      final broken = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        prices: doc.prices,
        fxRates: [
          ...doc.fxRates,
          FxRate(
            baseCurrency: 'EUR',
            quoteCurrency: 'USD',
            pricedOn: parseIsoDate('2026-03-20'),
            rate: Decimal.parse('0'),
            provider: 'ecb',
          ),
        ],
      );
      // 1.1 still converts the cash; the zero rate is skipped, not divided by.
      expect(
        FxConverter(broken, provider: 'ecb').convertMinor(
          40000,
          from: 'USD',
          to: 'EUR',
          asOf: parseIsoDate('2026-03-31'),
        ),
        36364,
      );
      final report = _report(broken, const ['acc-usd']);
      expect(report.cashMinor, isNull);
      expect(report.unavailable, contains(contains('rate must be positive')));
    });

    test('ignores broken rows this report could never read', () {
      final doc = _doc(foreignTrade: true);
      final elsewhere = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        prices: [
          ...doc.prices,
          // Another provider, and a row dated after the valuation: neither is
          // an observation `priceAt` can select for this report.
          Price(
            instrumentId: 'ins-1',
            pricedOn: parseIsoDate('2026-03-20'),
            priceMinor: -500,
            currency: 'EUR',
            provider: 'manual',
          ),
          Price(
            instrumentId: 'ins-1',
            pricedOn: parseIsoDate('2026-04-05'),
            priceMinor: -500,
            currency: 'EUR',
            provider: 'stooq',
          ),
        ],
        fxRates: [
          ...doc.fxRates,
          FxRate(
            baseCurrency: 'EUR',
            quoteCurrency: 'USD',
            pricedOn: parseIsoDate('2026-03-20'),
            rate: Decimal.parse('0'),
            provider: 'manual',
          ),
          FxRate(
            baseCurrency: 'EUR',
            quoteCurrency: 'USD',
            pricedOn: parseIsoDate('2026-04-05'),
            rate: Decimal.parse('0'),
            provider: 'ecb',
          ),
        ],
      );
      // The tracker does not validate, but none of its broken rows belongs to
      // this provider on or before this date.
      expect(validateTracker(elsewhere), isNotEmpty);
      final report = _report(elsewhere, const ['acc-usd']);
      expect(report.unavailable, ['Cost and realized gains in USD need a '
          'historical conversion policy to EUR']);
      expect(report.valueMinor, 10000);
      expect(report.cashMinor, 36364);
    });

    test('an impossible sell elsewhere does not reach this portfolio', () {
      final doc = _doc();
      final oversold = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: [
          ...doc.transactions,
          _tx('t7', 55000, 'acc-alt', tradeId: 'tr4'),
        ],
        trades: [
          ...doc.trades,
          // acc-alt holds 1 unit and sells 10: the FIFO books of that account
          // cannot be computed at all.
          Trade(
            id: 'tr4',
            accountId: 'acc-alt',
            instrumentId: 'ins-1',
            tradedOn: parseIsoDate('2026-03-10'),
            side: TradeSide.sell,
            units: Decimal.parse('10'),
            priceMinor: 5500,
            currency: 'EUR',
          ),
        ],
        prices: doc.prices,
        fxRates: doc.fxRates,
      );
      expect(
        () => FinanceEngine.holdings(oversold),
        throwsA(isA<FinanceError>()),
      );
      expect(_report(oversold, const ['acc-eur']).totalMinor, 32000);

      final broken = _report(oversold, const ['acc-alt']);
      expect(broken.totalMinor, isNull);
      expect(broken.unavailable.first, contains('sells more units'));
    });

    test('a balance past the exact range elsewhere does not reach it', () {
      final doc = _doc();
      final overflowed = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        // Two rows the platform holds exactly, whose sum it does not.
        transactions: [
          ...doc.transactions,
          _tx('t7', 9007199254740991, 'acc-cash'),
          _tx('t8', 9007199254740991, 'acc-cash'),
        ],
        trades: doc.trades,
        prices: doc.prices,
        fxRates: doc.fxRates,
      );
      expect(
        () => FinanceEngine.accountBalances(overflowed),
        throwsA(isA<RangeError>()),
      );
      expect(_report(overflowed, const ['acc-eur']).totalMinor, 32000);
    });

    test('ignores a rejected price in a currency it never quotes', () {
      final doc = _doc();
      final otherCurrency = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: const {'EUR': 2, 'USD': 2, 'GBP': 2},
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        prices: [
          ...doc.prices,
          // The position settles in EUR and its instrument is quoted in EUR, so
          // marketValue never asks for a GBP quote of it.
          Price(
            instrumentId: 'ins-1',
            pricedOn: parseIsoDate('2026-03-20'),
            priceMinor: -500,
            currency: 'GBP',
            provider: 'stooq',
          ),
        ],
        fxRates: doc.fxRates,
      );
      final report = _report(otherCurrency, const ['acc-eur']);
      expect(report.valueMinor, 22000);
      expect(report.unavailable, isEmpty);
    });

    test('a broken rate cannot withhold a report that converts nothing', () {
      final doc = _doc();
      final brokenPair = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        transactions: doc.transactions,
        trades: doc.trades,
        prices: doc.prices,
        fxRates: [
          FxRate(
            baseCurrency: 'EUR',
            quoteCurrency: 'USD',
            pricedOn: parseIsoDate('2026-03-01'),
            rate: Decimal.parse('0'),
            provider: 'ecb',
          ),
        ],
      );
      // acc-eur holds and settles in the reporting currency, so no leg of that
      // pair is ever resolved for it.
      final report = _report(brokenPair, const ['acc-eur']);
      expect(report.totalMinor, 32000);
      expect(report.unavailable, isEmpty);
    });

    test('an incomplete movement elsewhere leaves this portfolio alone', () {
      final doc = _doc();
      final other = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        // The other portfolio's buy settles in April; this one is untouched.
        transactions: [
          for (final t in doc.transactions)
            if (t.id != 't4') t else _tx('t4', -5000, 'acc-alt',
                tradeId: 'tr2', bookedOn: '2026-04-02'),
        ],
        trades: doc.trades,
        prices: doc.prices,
        fxRates: doc.fxRates,
      );
      expect(_report(other, const ['acc-eur']).totalMinor, 32000);
      expect(_report(other, const ['acc-alt']).totalMinor, isNull);
      // The combined summary includes the broken account, so it withholds.
      expect(
        _report(other, const ['acc-eur', 'acc-alt']).totalMinor,
        isNull,
      );
    });

    test('a transfer in transit into the portfolio withholds it', () {
      final doc = _doc();
      final inTransit = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        categories: const {
          'cat-1': Category(
            id: 'cat-1',
            name: 'Transfer',
            type: CategoryType.transfer,
          ),
        },
        instruments: doc.instruments,
        // The cash left the outside account in March and arrives in April, so
        // the portfolio's own accounts hold only one leg of the movement.
        transactions: [
          ...doc.transactions,
          _transferLeg('t8', -10000, 'acc-cash', '2026-03-20'),
          _transferLeg('t9', 10000, 'acc-eur', '2026-04-02'),
        ],
        trades: doc.trades,
        prices: doc.prices,
        fxRates: doc.fxRates,
      );
      expect(_report(inTransit, const ['acc-eur']).totalMinor, isNull);
      // The other portfolio has no leg of it and still reports.
      expect(_report(inTransit, const ['acc-alt']).totalMinor, 16000);
    });

    test('is unavailable while a trade is only half recorded', () {
      final doc = _doc();
      final pending = TrackerDocument(
        trackerId: doc.trackerId,
        baseCurrency: doc.baseCurrency,
        currencies: doc.currencies,
        accounts: doc.accounts,
        portfolios: doc.portfolios,
        instruments: doc.instruments,
        // The buy executed in March; its cash settles in April.
        transactions: [
          for (final t in doc.transactions)
            if (t.id != 't2') t else _tx('t2', -20000, 'acc-eur',
                tradeId: 'tr1', bookedOn: '2026-04-02'),
        ],
        trades: doc.trades,
        prices: doc.prices,
        fxRates: doc.fxRates,
      );
      final report = _report(pending, const ['acc-eur']);
      expect(report.valueMinor, isNull);
      expect(report.cashMinor, isNull);
      expect(report.costMinor, isNull);
      expect(report.unavailable.single, contains('half recorded on 2026-03-31'));
    });
  });

  group('validation', () {
    ValidationError? errorFor(Account account) {
      final doc = TrackerDocument(
        trackerId: 'trk-1',
        baseCurrency: 'EUR',
        currencies: const {'EUR': 2},
        accounts: {account.id: account},
        portfolios: const {'pf-1': Portfolio(id: 'pf-1', name: 'Retirement')},
      );
      return validateTracker(doc).firstOrNull;
    }

    test('rejects an unknown portfolio reference', () {
      expect(
        errorFor(
          const Account(
            id: 'acc-1',
            name: 'Broker',
            type: 'brokerage',
            currency: 'EUR',
            portfolioId: 'pf-missing',
          ),
        )?.message,
        'Unknown portfolio_id pf-missing',
      );
    });

    test('rejects a portfolio on a cash account', () {
      expect(
        errorFor(
          const Account(
            id: 'acc-1',
            name: 'Checking',
            type: 'cash',
            currency: 'EUR',
            portfolioId: 'pf-1',
          ),
        )?.message,
        contains('Only an investment account'),
      );
    });

    test('accepts an investment account without a portfolio', () {
      expect(
        errorFor(
          const Account(
            id: 'acc-1',
            name: 'Broker',
            type: 'brokerage',
            currency: 'EUR',
          ),
        ),
        isNull,
      );
    });
  });
}
