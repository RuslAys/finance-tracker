import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/schema.dart';
import 'package:flutter_test/flutter_test.dart';

const _eur = Account(id: 'acc-1', name: 'EUR', type: 'cash', currency: 'EUR');
const _usd = Account(id: 'acc-2', name: 'USD', type: 'cash', currency: 'USD');
const _eur2 = Account(id: 'acc-3', name: 'EUR 2', type: 'cash', currency: 'EUR');

TrackerDocument _doc({
  List<Transaction> transactions = const [],
  Map<String, Category> categories = const {},
  Map<String, Instrument> instruments = const {},
  List<Trade> trades = const [],
  List<Price> prices = const [],
  List<FxRate> fxRates = const [],
  Map<String, ImportStatus> imports = const {},
}) => TrackerDocument(
  trackerId: 'trk-1',
  baseCurrency: 'EUR',
  currencies: const {'EUR': 2, 'USD': 2},
  accounts: const {'acc-1': _eur, 'acc-2': _usd, 'acc-3': _eur2},
  categories: categories,
  instruments: instruments,
  transactions: transactions,
  trades: trades,
  prices: prices,
  fxRates: fxRates,
  imports: imports,
);

Transaction _tx(
  String id,
  int amountMinor, {
  String accountId = 'acc-1',
  String currency = 'EUR',
  String? transferId,
  String? categoryId,
  String? tradeId,
  String source = 'manual',
  String sourceId = '',
  String importId = '',
}) => Transaction(
  id: id,
  accountId: accountId,
  bookedOn: parseIsoDate('2026-03-01'),
  amountMinor: amountMinor,
  currency: currency,
  transferId: transferId,
  categoryId: categoryId,
  tradeId: tradeId,
  source: source,
  sourceId: sourceId,
  importId: importId,
);

List<String> _messages(TrackerDocument doc) =>
    validateTracker(doc).map((error) => error.message).toList();

void main() {
  test('accepts a consistent document', () {
    expect(validateTracker(_doc(transactions: [_tx('t1', 100)])), isEmpty);
  });

  test('rejects a transaction currency that differs from its account', () {
    expect(
      _messages(_doc(transactions: [_tx('t1', 100, currency: 'USD')])),
      contains(startsWith('Currency USD differs from account currency EUR')),
    );
  });

  test('rejects an unbalanced or same-account transfer', () {
    expect(
      _messages(
        _doc(
          transactions: [
            _tx('t1', -2000, transferId: 'trf-1'),
            _tx('t2', 1900, accountId: 'acc-2', currency: 'USD',
                transferId: 'trf-1'),
          ],
        ),
      ),
      containsAll([
        'Transfer legs use different currencies; v1 has no cross-currency transfer',
        'Transfer legs do not sum to zero',
      ]),
    );

    expect(
      _messages(_doc(transactions: [_tx('t1', -2000, transferId: 'trf-1')])),
      contains('transfer_id has 1 legs, expected 2'),
    );
  });

  test('rejects duplicate ids and unknown references', () {
    expect(
      _messages(
        _doc(transactions: [_tx('t1', 100), _tx('t1', 100, accountId: 'nope')]),
      ),
      containsAll(['Duplicate id', 'Unknown account_id nope']),
    );
  });

  test('rejects a category cycle and a parent of another type', () {
    final messages = _messages(
      _doc(
        categories: const {
          'cat-1': Category(
            id: 'cat-1',
            name: 'A',
            type: CategoryType.expense,
            parentId: 'cat-2',
          ),
          'cat-2': Category(
            id: 'cat-2',
            name: 'B',
            type: CategoryType.expense,
            parentId: 'cat-1',
          ),
          'cat-3': Category(
            id: 'cat-3',
            name: 'C',
            type: CategoryType.income,
            parentId: 'cat-1',
          ),
        },
      ),
    );
    expect(messages, contains('Parent links form a cycle'));
    expect(messages, contains('Parent type expense differs from income'));
  });

  test('rejects a transfer leg without a transfer category', () {
    expect(
      _messages(
        _doc(
          transactions: [
            _tx('t1', -2000, transferId: 'trf-1'),
            _tx('t2', 2000, accountId: 'acc-2', transferId: 'trf-1'),
          ],
        ),
      ),
      contains('Transfer leg needs a transfer category'),
    );
  });

  test('rejects a transfer category without a transfer_id', () {
    const categories = {
      'cat-1': Category(id: 'cat-1', name: 'Move', type: CategoryType.transfer),
    };
    expect(
      _messages(
        _doc(
          categories: categories,
          transactions: [_tx('t1', -2000, categoryId: 'cat-1', transferId: '')],
        ),
      ),
      ['Transfer category needs a transfer_id'],
    );
    expect(
      _messages(
        _doc(
          categories: categories,
          transactions: [
            _tx('t1', -2000, categoryId: 'cat-1', transferId: 'trf-1'),
            _tx('t2', 2000,
                accountId: 'acc-3', categoryId: 'cat-1', transferId: 'trf-1'),
          ],
        ),
      ),
      isEmpty,
    );
  });

  test('rejects a repeated bank identity on transactions and trades', () {
    expect(
      _messages(
        _doc(
          transactions: [
            _tx('t1', -2000, source: 'revolut', sourceId: 'bank-1'),
            _tx('t2', -2000, source: 'revolut', sourceId: 'bank-1'),
            // A blank source_id is never an identity, so these are not duplicates.
            _tx('t3', -500),
            _tx('t4', -500),
          ],
        ),
      ),
      ['Duplicate bank identity (account_id, source, source_id)'],
    );

    expect(
      _messages(
        _doc(
          instruments: const {
            'ins-1': Instrument(
              id: 'ins-1',
              symbol: 'VWCE',
              name: 'World ETF',
              type: 'etf',
              currency: 'EUR',
            ),
          },
          trades: [
            for (final id in ['tr1', 'tr2'])
              Trade(
                id: id,
                accountId: 'acc-1',
                instrumentId: 'ins-1',
                tradedOn: parseIsoDate('2026-03-01'),
                side: TradeSide.buy,
                units: Decimal.parse('1'),
                priceMinor: 2500,
                currency: 'EUR',
                source: 'broker',
                sourceId: 'exec-1',
              ),
          ],
        ),
      ),
      // Both trades also lack a settlement transaction, which this case is not
      // about.
      contains('Duplicate bank identity (account_id, source, source_id)'),
    );
  });

  test('rejects a stored amount outside the exact minor-unit range', () {
    expect(
      _messages(_doc(transactions: [_tx('t1', 9007199254740992)])),
      ['amount_minor is outside the exact minor-unit range'],
    );
    expect(
      _messages(_doc(transactions: [_tx('t1', 9007199254740991)])),
      isEmpty,
    );
  });

  test('rejects an instrument currency without a currencies row', () {
    expect(
      _messages(
        _doc(
          instruments: const {
            'ins-1': Instrument(
              id: 'ins-1',
              symbol: '7203',
              name: 'Toyota',
              type: 'stock',
              currency: 'JPY',
            ),
          },
        ),
      ),
      contains('Currency JPY has no currencies row'),
    );
  });

  group('trade settlement', () {
    const instruments = {
      'ins-1': Instrument(
        id: 'ins-1',
        symbol: 'VWCE',
        name: 'World ETF',
        type: 'etf',
        currency: 'EUR',
      ),
    };

    // 2 units at 100.00 with a 1.00 fee: a buy costs 201.00, a sell nets 199.00.
    Trade trade({TradeSide side = TradeSide.buy, String importId = ''}) => Trade(
      id: 'tr1',
      accountId: 'acc-1',
      instrumentId: 'ins-1',
      tradedOn: parseIsoDate('2026-03-01'),
      side: side,
      units: Decimal.parse('2'),
      priceMinor: 10000,
      currency: 'EUR',
      feeMinor: 100,
      importId: importId,
    );

    List<String> messages({
      List<Transaction> transactions = const [],
      TradeSide side = TradeSide.buy,
      String importId = '',
      Map<String, ImportStatus> imports = const {},
      Map<String, Category> categories = const {},
    }) => _messages(
      _doc(
        instruments: instruments,
        trades: [trade(side: side, importId: importId)],
        transactions: transactions,
        imports: imports,
        categories: categories,
      ),
    );

    test('accepts the matching buy and sell settlements', () {
      expect(messages(transactions: [_tx('t1', -20100, tradeId: 'tr1')]), isEmpty);
      expect(
        messages(
          side: TradeSide.sell,
          transactions: [_tx('t1', 19900, tradeId: 'tr1')],
        ),
        isEmpty,
      );
    });

    test('rejects a missing or repeated settlement', () {
      expect(
        messages(),
        contains('Trade needs exactly one settlement transaction, found 0'),
      );
      expect(
        messages(
          transactions: [
            _tx('t1', -20100, tradeId: 'tr1'),
            _tx('t2', -20100, tradeId: 'tr1'),
          ],
        ),
        contains('Trade needs exactly one settlement transaction, found 2'),
      );
    });

    test('rejects a settlement that does not match the trade', () {
      // The fee is missing from the cash movement.
      expect(
        messages(transactions: [_tx('t1', -20000, tradeId: 'tr1')]),
        contains('Settlement amount -20000 is not -20100'),
      );
      // A buy that credits the account instead of debiting it.
      expect(
        messages(transactions: [_tx('t1', 20100, tradeId: 'tr1')]),
        contains('Settlement amount 20100 is not -20100'),
      );
      expect(
        messages(
          transactions: [_tx('t1', -20100, accountId: 'acc-3', tradeId: 'tr1')],
        ),
        contains('Settlement transaction is in account acc-3, not acc-1'),
      );
    });

    test('rejects a settlement staged by a different import', () {
      const imports = {
        'imp-1': ImportStatus.committed,
        'imp-2': ImportStatus.pending,
      };
      // The trade is visible to every calculation while its cash debit is not.
      expect(
        messages(
          importId: 'imp-1',
          imports: imports,
          transactions: [_tx('t1', -20100, tradeId: 'tr1', importId: 'imp-2')],
        ),
        contains('Settlement transaction has import_id "imp-2", not "imp-1"'),
      );
      expect(
        messages(
          importId: 'imp-1',
          imports: imports,
          transactions: [_tx('t1', -20100, tradeId: 'tr1', importId: 'imp-1')],
        ),
        isEmpty,
      );
    });

    test('rejects a settlement that is also a transfer leg', () {
      const categories = {
        'cat-1': Category(id: 'cat-1', name: 'Move', type: CategoryType.transfer),
      };
      // Both validators are satisfied, yet the offsetting leg leaves the same
      // cash in another account while the position is added.
      expect(
        messages(
          categories: categories,
          transactions: [
            _tx('t1', -20100,
                tradeId: 'tr1', transferId: 'trf-1', categoryId: 'cat-1'),
            _tx('t2', 20100,
                accountId: 'acc-3', transferId: 'trf-1', categoryId: 'cat-1'),
          ],
        ),
        contains('A trade settlement cannot also be a transfer leg'),
      );
    });

    test('rejects a trade_id that references no trade', () {
      expect(
        _messages(_doc(transactions: [_tx('t1', -20100, tradeId: 'nope')])),
        contains('Unknown trade_id nope'),
      );
    });
  });

  test('rejects a duplicate price key and an unpriceable instrument', () {
    Price price(String provider) => Price(
      instrumentId: 'ins-1',
      pricedOn: parseIsoDate('2026-03-01'),
      priceMinor: 20000,
      currency: 'EUR',
      provider: provider,
    );
    const instruments = {
      'ins-1': Instrument(
        id: 'ins-1',
        symbol: 'VWCE',
        name: 'World ETF',
        type: 'etf',
        currency: 'EUR',
      ),
    };
    expect(
      _messages(
        _doc(
          instruments: instruments,
          prices: [price('stooq'), price('stooq'), price('other')],
        ),
      ),
      ['Duplicate composite key'],
    );
    expect(
      _messages(_doc(prices: [price('stooq')])),
      contains('Unknown instrument_id ins-1'),
    );
  });

  test('rejects an fx rate that is not positive or has no currencies row', () {
    FxRate rate(String quote, String value) => FxRate(
      baseCurrency: 'EUR',
      quoteCurrency: quote,
      pricedOn: parseIsoDate('2026-03-01'),
      rate: Decimal.parse(value),
      provider: 'ecb',
    );
    expect(_messages(_doc(fxRates: [rate('USD', '1.1')])), isEmpty);
    expect(
      _messages(_doc(fxRates: [rate('USD', '0'), rate('CHF', '1.1')])),
      containsAll([
        'rate must be positive',
        'Currency CHF has no currencies row',
      ]),
    );
    expect(
      _messages(_doc(fxRates: [rate('USD', '1.1'), rate('USD', '1.2')])),
      ['Duplicate composite key'],
    );
  });

  test('rejects a date that is not YYYY-MM-DD', () {
    expect(() => parseIsoDate('01/03/2026'), throwsFormatException);
    expect(() => parseIsoDate('2026-02-30'), throwsFormatException);
  });
}
