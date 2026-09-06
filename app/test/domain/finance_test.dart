import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/finance.dart';
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
  Map<String, ImportStatus> imports = const {},
}) => TrackerDocument(
  trackerId: 'trk-1',
  baseCurrency: 'EUR',
  currencies: const {'EUR': 2},
  accounts: const {'acc-1': _checking, 'acc-2': _savings, 'acc-3': _broker},
  categories: const {'cat-1': _salary, 'cat-2': _groceries, 'cat-3': _transfer},
  instruments: const {'ins-1': _etf},
  transactions: transactions,
  trades: trades,
  imports: imports,
);

Transaction _tx(
  String id,
  int amountMinor, {
  String accountId = 'acc-1',
  String? categoryId,
  String? transferId,
  String importId = '',
  String bookedOn = '2026-03-01',
}) => Transaction(
  id: id,
  accountId: accountId,
  bookedOn: parseIsoDate(bookedOn),
  amountMinor: amountMinor,
  currency: 'EUR',
  categoryId: categoryId,
  transferId: transferId,
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

    test('counts a row whose transfer_id cell is blank', () {
      final flow = FinanceEngine.cashFlow(
        _doc(transactions: [_tx('t1', -700, categoryId: 'cat-2', transferId: '')]),
        currency: 'EUR',
      );
      expect(flow.expenseByCategory, {'cat-2': 700});
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
}
