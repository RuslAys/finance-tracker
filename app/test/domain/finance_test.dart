import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/finance.dart';
import 'package:finance_tracker/domain/fx.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _checking = Account(
  id: 'acc-1',
  name: 'Checking',
  type: 'cash',
  currency: 'EUR',
);
const _savings = Account(
  id: 'acc-2',
  name: 'Savings',
  type: 'cash',
  currency: 'EUR',
);
const _broker = Account(
  id: 'acc-3',
  name: 'Broker',
  type: 'brokerage',
  currency: 'EUR',
);
const _etf = Instrument(
  id: 'ins-1',
  symbol: 'VWCE',
  name: 'World ETF',
  type: 'etf',
  currency: 'EUR',
);
/// Same instrument, quoted in a currency its trades do not settle in.
const _usdEtf = Instrument(
  id: 'ins-1',
  symbol: 'VWCE',
  name: 'World ETF',
  type: 'etf',
  currency: 'USD',
);
const _salary = Category(id: 'cat-1', name: 'Salary', type: CategoryType.income);
const _groceries = Category(
  id: 'cat-2',
  name: 'Groceries',
  type: CategoryType.expense,
);
const _transfer = Category(
  id: 'cat-3',
  name: 'Transfer',
  type: CategoryType.transfer,
);

TrackerDocument _doc({
  List<Transaction> transactions = const [],
  List<Trade> trades = const [],
  List<Price> prices = const [],
  List<FxRate> fxRates = const [],
  Map<String, ImportStatus> imports = const {},
  Map<String, int> currencies = const {'EUR': 2},
  Instrument instrument = _etf,
}) => TrackerDocument(
  trackerId: 'trk-1',
  baseCurrency: 'EUR',
  currencies: currencies,
  accounts: const {'acc-1': _checking, 'acc-2': _savings, 'acc-3': _broker},
  categories: const {'cat-1': _salary, 'cat-2': _groceries, 'cat-3': _transfer},
  instruments: {'ins-1': instrument},
  transactions: transactions,
  trades: trades,
  prices: prices,
  fxRates: fxRates,
  imports: imports,
);

Price _price(
  int priceMinor, {
  String pricedOn = '2026-03-01',
  String provider = 'stooq',
  String currency = 'EUR',
}) => Price(
  instrumentId: 'ins-1',
  pricedOn: parseIsoDate(pricedOn),
  priceMinor: priceMinor,
  currency: currency,
  provider: provider,
);

FxRate _rate(String rate, String pricedOn) => FxRate(
  baseCurrency: 'EUR',
  quoteCurrency: 'USD',
  pricedOn: parseIsoDate(pricedOn),
  rate: Decimal.parse(rate),
  provider: 'ecb',
);

Transaction _tx(
  String id,
  int amountMinor, {
  String accountId = 'acc-1',
  String? categoryId,
  String? transferId,
  String? tradeId,
  String importId = '',
  String bookedOn = '2026-03-01',
  String currency = 'EUR',
}) => Transaction(
  id: id,
  accountId: accountId,
  bookedOn: parseIsoDate(bookedOn),
  amountMinor: amountMinor,
  currency: currency,
  categoryId: categoryId,
  transferId: transferId,
  tradeId: tradeId,
  importId: importId,
);

Trade _trade(
  String id,
  TradeSide side,
  String units,
  int priceMinor, {
  int feeMinor = 0,
  String tradedOn = '2026-03-01',
  String importId = '',
}) => Trade(
  id: id,
  accountId: 'acc-3',
  instrumentId: 'ins-1',
  tradedOn: parseIsoDate(tradedOn),
  side: side,
  units: Decimal.parse(units),
  priceMinor: priceMinor,
  currency: 'EUR',
  feeMinor: feeMinor,
  importId: importId,
);

void main() {
  group('accountBalances', () {
    test('sums signed amounts and reports untouched accounts as zero', () {
      final balances = FinanceEngine.accountBalances(
        _doc(transactions: [_tx('t1', 100000), _tx('t2', -2550)]),
      );
      expect(balances['acc-1'], 97450);
      expect(balances['acc-2'], 0);
    });

    test('excludes rows of an import that has not committed', () {
      final doc = _doc(
        transactions: [
          _tx('t1', 100000, importId: 'imp-1'),
          _tx('t2', 500, importId: 'imp-2'),
          _tx('t3', 25, importId: 'imp-3'),
        ],
        imports: const {
          'imp-1': ImportStatus.committed,
          'imp-2': ImportStatus.pending,
          'imp-3': ImportStatus.failed,
        },
      );
      expect(FinanceEngine.accountBalances(doc)['acc-1'], 100000);
    });
  });

  group('cashFlow', () {
    test('treats a refund as reduced expense, not income', () {
      final flow = FinanceEngine.cashFlow(
        _doc(
          transactions: [
            _tx('t1', 100000, categoryId: 'cat-1'),
            _tx('t2', -5000, categoryId: 'cat-2'),
            _tx('t3', 1200, categoryId: 'cat-2'),
          ],
        ),
        currency: 'EUR',
      );
      expect(flow.incomeByCategory['cat-1'], 100000);
      expect(flow.expenseByCategory['cat-2'], 3800);
      expect(flow.net, 96200);
    });

    test('excludes transfers and rows outside the period', () {
      final flow = FinanceEngine.cashFlow(
        _doc(
          transactions: [
            _tx('t1', -2000,
                categoryId: 'cat-3', transferId: 'trf-1'),
            _tx('t2', 2000,
                accountId: 'acc-2', categoryId: 'cat-3', transferId: 'trf-1'),
            _tx('t3', -900, categoryId: 'cat-2', bookedOn: '2026-02-01'),
            _tx('t4', -100, categoryId: 'cat-2', bookedOn: '2026-03-15'),
          ],
        ),
        currency: 'EUR',
        from: parseIsoDate('2026-03-01'),
        to: parseIsoDate('2026-03-31'),
      );
      expect(flow.expenseByCategory, {'cat-2': 100});
      expect(flow.totalIncome, 0);
    });

    test('excludes a trade settlement, which is not spending', () {
      final flow = FinanceEngine.cashFlow(
        _doc(
          transactions: [
            _tx('t1', -20100, accountId: 'acc-3', tradeId: 'tr1'),
            _tx('t2', -700, categoryId: 'cat-2'),
          ],
        ),
        currency: 'EUR',
      );
      expect(flow.expenseByCategory, {'cat-2': 700});
    });

    test('counts a row whose transfer_id cell is blank', () {
      final flow = FinanceEngine.cashFlow(
        _doc(transactions: [_tx('t1', -700, categoryId: 'cat-2', transferId: '')]),
        currency: 'EUR',
      );
      expect(flow.expenseByCategory, {'cat-2': 700});
    });

    test('converts a foreign row at its booking date, not the latest rate', () {
      final doc = _doc(
        currencies: const {'EUR': 2, 'USD': 2},
        transactions: [
          _tx('t1', 100000, categoryId: 'cat-1'),
          _tx(
            't2',
            -12000,
            accountId: 'acc-2',
            categoryId: 'cat-2',
            currency: 'USD',
            bookedOn: '2026-03-10',
          ),
        ],
        fxRates: [_rate('1.2', '2026-03-01'), _rate('1.5', '2026-03-20')],
      );
      final flow = FinanceEngine.cashFlow(
        doc,
        currency: 'EUR',
        from: parseIsoDate('2026-03-01'),
        to: parseIsoDate('2026-03-31'),
        fx: FxConverter(doc, provider: 'ecb'),
      );
      // 120.00 USD at the 1.2 rate of the booking date is 100.00 EUR; the later
      // 1.5 rate would have reported 80.00.
      expect(flow.expenseByCategory, {'cat-2': 10000});
      expect(flow.net, 90000);
    });

    test('makes totals unavailable when a row has no rate on its date', () {
      final doc = _doc(
        currencies: const {'EUR': 2, 'USD': 2},
        transactions: [
          _tx('t1', 100000, categoryId: 'cat-1'),
          _tx(
            't2',
            -12000,
            accountId: 'acc-2',
            categoryId: 'cat-2',
            currency: 'USD',
            bookedOn: '2026-03-10',
          ),
        ],
        // Observed only after the row was booked, so the row cannot be valued.
        fxRates: [_rate('1.2', '2026-03-20')],
      );
      final flow = FinanceEngine.cashFlow(
        doc,
        currency: 'EUR',
        fx: FxConverter(doc, provider: 'ecb'),
      );
      expect(flow.unconvertedCurrencies, {'USD'});
      expect(flow.isComplete, isFalse);
      expect(flow.totalIncome, isNull);
      expect(flow.totalExpense, isNull);
      expect(flow.net, isNull);
    });

    test('reports a foreign row rather than dropping it without a converter', () {
      final flow = FinanceEngine.cashFlow(
        _doc(
          currencies: const {'EUR': 2, 'USD': 2},
          transactions: [
            _tx('t1', -700, accountId: 'acc-2', categoryId: 'cat-2',
                currency: 'USD'),
          ],
        ),
        currency: 'EUR',
      );
      expect(flow.unconvertedCurrencies, {'USD'});
      expect(flow.net, isNull);
    });
  });

  group('as-of filtering', () {
    test('excludes cash and trades booked after the valuation date', () {
      final doc = _doc(
        transactions: [
          _tx('t1', 100000, bookedOn: '2026-03-01'),
          _tx('t2', -2000, bookedOn: '2026-04-01'),
        ],
        trades: [
          _trade('tr1', TradeSide.buy, '1', 10000, tradedOn: '2026-03-01'),
          _trade('tr2', TradeSide.buy, '5', 10000, tradedOn: '2026-04-01'),
        ],
      );
      final asOf = parseIsoDate('2026-03-31');
      expect(FinanceEngine.accountBalances(doc, asOf: asOf)['acc-1'], 100000);
      expect(FinanceEngine.accountBalances(doc)['acc-1'], 98000);
      expect(
        FinanceEngine.holdings(doc, asOf: asOf).single.units,
        Decimal.parse('1'),
      );
      expect(FinanceEngine.holdings(doc).single.units, Decimal.parse('6'));
    });

    test('net worth is unavailable while a trade is unsettled', () {
      // 100.00 cash, a 100.00 buy executed on the 10th, its cash leaving on the
      // 12th. On the 11th the document holds the position and the cash that
      // bought it, so no defined total exists.
      final doc = _doc(
        transactions: [
          _tx('t1', 10000, accountId: 'acc-3', bookedOn: '2026-03-01'),
          _tx('t2', -10000,
              accountId: 'acc-3', tradeId: 'tr1', bookedOn: '2026-03-12'),
        ],
        trades: [
          _trade('tr1', TradeSide.buy, '1', 10000, tradedOn: '2026-03-10'),
        ],
        prices: [_price(10000, pricedOn: '2026-03-01')],
      );
      Minor? at(String date) => FinanceEngine.netWorth(
        doc,
        priceProvider: 'stooq',
        rateProvider: 'ecb',
        asOf: parseIsoDate(date),
      );
      expect(at('2026-03-11'), isNull);
      // Before the trade it is plain cash; after settlement, the position.
      expect(at('2026-03-09'), 10000);
      expect(at('2026-03-12'), 10000);
    });

    test('net worth is unavailable while a transfer is in transit', () {
      // 100.00 leaves one account on the 10th and lands in the other on the
      // 12th. On the 11th the money is recorded nowhere; it has not vanished.
      final doc = _doc(
        transactions: [
          _tx('t1', 10000, bookedOn: '2026-03-01'),
          _tx('t2', -10000,
              categoryId: 'cat-3', transferId: 'trf-1', bookedOn: '2026-03-10'),
          _tx('t3', 10000,
              accountId: 'acc-2',
              categoryId: 'cat-3',
              transferId: 'trf-1',
              bookedOn: '2026-03-12'),
        ],
      );
      Minor? at(String date) => FinanceEngine.netWorth(
        doc,
        priceProvider: 'stooq',
        rateProvider: 'ecb',
        asOf: parseIsoDate(date),
      );
      expect(at('2026-03-11'), isNull);
      expect(at('2026-03-09'), 10000);
      expect(at('2026-03-12'), 10000);
    });

    test('net worth values the position the tracker held on that date', () {
      final doc = _doc(
        transactions: [
          _tx('t1', 20000, accountId: 'acc-3'),
          _tx('t2', -20000, accountId: 'acc-3', tradeId: 'tr1'),
          // Both booked after the valuation date, so neither may count.
          _tx('t3', 500000, accountId: 'acc-1', bookedOn: '2026-04-05'),
        ],
        trades: [
          _trade('tr1', TradeSide.buy, '2', 10000),
          _trade('tr2', TradeSide.buy, '9', 10000, tradedOn: '2026-04-05'),
        ],
        prices: [_price(11000)],
      );
      expect(
        FinanceEngine.netWorth(
          doc,
          priceProvider: 'stooq',
          rateProvider: 'ecb',
          asOf: parseIsoDate('2026-03-31'),
        ),
        22000,
      );
    });
  });

  group('holdings', () {
    test('capitalizes buy fees and realizes FIFO gain on a partial sell', () {
      final holdings = FinanceEngine.holdings(
        _doc(
          trades: [
            _trade('tr1', TradeSide.buy, '10', 1500,
                feeMinor: 100, tradedOn: '2026-01-05'),
            _trade('tr2', TradeSide.buy, '5', 2000, tradedOn: '2026-02-05'),
            _trade('tr3', TradeSide.sell, '12', 2500,
                feeMinor: 50, tradedOn: '2026-03-05'),
          ],
        ),
      );
      expect(holdings, hasLength(1));
      final holding = holdings.single;
      expect(holding.units, Decimal.parse('3'));
      // 10000 minor units of the second lot, less the 4000 sold from it.
      expect(holding.costMinor, 6000);
      // 29950 proceeds less 15100 and 4000 of FIFO cost.
      expect(holding.realizedGainMinor, 10850);
    });

    test('keeps fractional units exact', () {
      final holdings = FinanceEngine.holdings(
        _doc(
          trades: [
            _trade('tr1', TradeSide.buy, '0.1', 33333),
            _trade('tr2', TradeSide.buy, '0.2', 33333, tradedOn: '2026-03-02'),
          ],
        ),
      );
      expect(holdings.single.units, Decimal.parse('0.3'));
      // Each notional rounds once: 3333.3 and 6666.6 minor units.
      expect(holdings.single.costMinor, 3333 + 6667);
    });

    test('refuses a lot cost that leaves the exact minor-unit range', () {
      // The notional alone is representable; adding the fee is not.
      expect(
        () => FinanceEngine.holdings(
          _doc(
            trades: [
              _trade('tr1', TradeSide.buy, '1', 9007199254740991, feeMinor: 1),
            ],
          ),
        ),
        throwsRangeError,
      );
    });

    test('rejects a sell without matching lots', () {
      expect(
        () => FinanceEngine.holdings(
          _doc(trades: [_trade('tr1', TradeSide.sell, '1', 2500)]),
        ),
        throwsA(isA<FinanceError>()),
      );
    });

    test('ignores trades of an import that has not committed', () {
      final holdings = FinanceEngine.holdings(
        _doc(
          trades: [_trade('tr1', TradeSide.buy, '1', 2500, importId: 'imp-1')],
          imports: const {'imp-1': ImportStatus.pending},
        ),
      );
      expect(holdings, isEmpty);
    });
  });

  group('marketValue', () {
    Holding holdingOf(TrackerDocument doc) =>
        FinanceEngine.holdings(doc).single;

    test('values units at the latest price on or before the as-of date', () {
      final doc = _doc(
        trades: [_trade('tr1', TradeSide.buy, '0.5', 10000)],
        prices: [
          _price(20000, pricedOn: '2026-03-01'),
          _price(30001, pricedOn: '2026-03-20'),
          _price(99999, pricedOn: '2026-04-02'),
        ],
      );
      // 0.5 x 300.01 = 150.005, rounded once away from zero.
      expect(
        FinanceEngine.marketValue(doc, holdingOf(doc),
            provider: 'stooq', asOf: parseIsoDate('2026-03-31')),
        (amount: 15001, currency: 'EUR'),
      );
      expect(
        FinanceEngine.marketValue(doc, holdingOf(doc),
            provider: 'stooq', asOf: parseIsoDate('2026-03-10')),
        (amount: 10000, currency: 'EUR'),
      );
    });

    test('falls back to a quote in the instrument reference currency', () {
      // The position settles in EUR but the instrument is quoted in USD only.
      final doc = _doc(
        currencies: const {'EUR': 2, 'USD': 2},
        instrument: _usdEtf,
        trades: [_trade('tr1', TradeSide.buy, '2', 10000)],
        prices: [_price(11000, currency: 'USD')],
      );
      expect(
        FinanceEngine.marketValue(doc, holdingOf(doc),
            provider: 'stooq', asOf: parseIsoDate('2026-03-31')),
        (amount: 22000, currency: 'USD'),
      );
    });

    test('is unavailable, not zero, without a matching price', () {
      final doc = _doc(
        trades: [_trade('tr1', TradeSide.buy, '1', 10000)],
        prices: [
          _price(20000, provider: 'other'),
          _price(20000, currency: 'USD'),
          _price(20000, pricedOn: '2026-04-02'),
        ],
      );
      expect(
        FinanceEngine.marketValue(doc, holdingOf(doc),
            provider: 'stooq', asOf: parseIsoDate('2026-03-31')),
        isNull,
      );
    });
  });

  group('netWorth', () {
    Minor? netWorth(TrackerDocument doc) => FinanceEngine.netWorth(
      doc,
      priceProvider: 'stooq',
      rateProvider: 'ecb',
      asOf: parseIsoDate('2026-03-31'),
    );

    // The buy's settlement cash leaves the account as its own transaction,
    // linked by trade_id as `docs/spreadsheet-format.md` requires. Without it
    // the funding cash would still be in the balance and every total below
    // would be 200.00 too high.
    final funded = [
      _tx('t1', 20000, accountId: 'acc-3'),
      _tx('t2', -20000, accountId: 'acc-3', tradeId: 'tr1'),
    ];

    test('sums cash and priced positions in the base currency', () {
      // 200.00 funded and spent on 2 units, now quoted at 110.00 each.
      expect(
        netWorth(
          _doc(
            transactions: funded,
            trades: [_trade('tr1', TradeSide.buy, '2', 10000)],
            prices: [_price(11000)],
          ),
        ),
        22000,
      );
    });

    test('converts a position quoted in a foreign currency', () {
      // 2 units at 110.00 USD, converted at 1.1 USD per EUR, no cash left.
      expect(
        netWorth(
          _doc(
            currencies: const {'EUR': 2, 'USD': 2},
            instrument: _usdEtf,
            transactions: funded,
            trades: [_trade('tr1', TradeSide.buy, '2', 10000)],
            prices: [_price(11000, currency: 'USD')],
            fxRates: [
              FxRate(
                baseCurrency: 'EUR',
                quoteCurrency: 'USD',
                pricedOn: parseIsoDate('2026-03-01'),
                rate: Decimal.parse('1.1'),
                provider: 'ecb',
              ),
            ],
          ),
        ),
        20000,
      );
    });

    test('is unavailable, not zero, when a position has no price', () {
      expect(
        netWorth(
          _doc(
            transactions: funded,
            trades: [_trade('tr1', TradeSide.buy, '2', 10000)],
          ),
        ),
        isNull,
      );
    });
  });
}
