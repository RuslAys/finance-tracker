/// A synthetic tracker so the screens have something to render.
///
/// No storage adapter exists yet, so the app opens this instead of a workbook
/// or Google Sheet. The values are invented; a real tracker never lives in the
/// repository. Delete this once `TrackerStore` can open a file.
library;

import '../domain/decimal.dart';
import '../domain/models.dart';
import 'tracker_controller.dart';

const sampleProvider = 'demo';

TrackerDocument sampleTracker() {
  final today = todayUtc();
  DateTime daysAgo(int days) => today.subtract(Duration(days: days));

  return TrackerDocument(
    trackerId: 'sample',
    baseCurrency: 'EUR',
    currencies: const {'EUR': 2, 'USD': 2},
    accounts: const {
      'acc-checking': Account(
        id: 'acc-checking',
        name: 'Checking',
        type: 'cash',
        currency: 'EUR',
      ),
      'acc-usd': Account(
        id: 'acc-usd',
        name: 'USD savings',
        type: 'cash',
        currency: 'USD',
      ),
      'acc-broker': Account(
        id: 'acc-broker',
        name: 'Broker',
        type: 'brokerage',
        currency: 'EUR',
      ),
    },
    categories: const {
      'cat-salary': Category(
        id: 'cat-salary',
        name: 'Salary',
        type: CategoryType.income,
      ),
      'cat-rent': Category(
        id: 'cat-rent',
        name: 'Rent',
        type: CategoryType.expense,
      ),
      'cat-groceries': Category(
        id: 'cat-groceries',
        name: 'Groceries',
        type: CategoryType.expense,
      ),
      'cat-transfer': Category(
        id: 'cat-transfer',
        name: 'Transfer',
        type: CategoryType.transfer,
      ),
    },
    instruments: const {
      'ins-etf': Instrument(
        id: 'ins-etf',
        symbol: 'VWCE',
        name: 'World ETF',
        type: 'etf',
        currency: 'EUR',
      ),
    },
    transactions: [
      Transaction(
        id: 'tx-1',
        accountId: 'acc-checking',
        bookedOn: daysAgo(24),
        amountMinor: 320000,
        currency: 'EUR',
        payee: 'Employer',
        categoryId: 'cat-salary',
      ),
      Transaction(
        id: 'tx-2',
        accountId: 'acc-checking',
        bookedOn: daysAgo(22),
        amountMinor: -115000,
        currency: 'EUR',
        payee: 'Landlord',
        categoryId: 'cat-rent',
      ),
      Transaction(
        id: 'tx-3',
        accountId: 'acc-checking',
        bookedOn: daysAgo(12),
        amountMinor: -8420,
        currency: 'EUR',
        payee: 'Supermarket',
        categoryId: 'cat-groceries',
      ),
      Transaction(
        id: 'tx-4',
        accountId: 'acc-checking',
        bookedOn: daysAgo(5),
        amountMinor: 1250,
        currency: 'EUR',
        payee: 'Supermarket',
        description: 'Returned item',
        categoryId: 'cat-groceries',
      ),
      Transaction(
        id: 'tx-5',
        accountId: 'acc-checking',
        bookedOn: daysAgo(70),
        amountMinor: -50000,
        currency: 'EUR',
        payee: 'Broker',
        categoryId: 'cat-transfer',
        transferId: 'trf-1',
      ),
      Transaction(
        id: 'tx-6',
        accountId: 'acc-broker',
        bookedOn: daysAgo(70),
        amountMinor: 50000,
        currency: 'EUR',
        payee: 'Checking',
        categoryId: 'cat-transfer',
        transferId: 'trf-1',
      ),
      // Each buy settles as cash out of the broker account, exactly as a broker
      // import would write it. Validation requires one such row per trade:
      // without it the invested cash would stay in the balance and net worth
      // would count the same money twice.
      Transaction(
        id: 'tx-8',
        accountId: 'acc-broker',
        bookedOn: daysAgo(60),
        amountMinor: -27725,
        currency: 'EUR',
        payee: 'VWCE buy',
        tradeId: 'trd-1',
      ),
      Transaction(
        id: 'tx-9',
        accountId: 'acc-broker',
        bookedOn: daysAgo(18),
        amountMinor: -14850,
        currency: 'EUR',
        payee: 'VWCE buy',
        tradeId: 'trd-2',
      ),
      Transaction(
        id: 'tx-7',
        accountId: 'acc-usd',
        bookedOn: daysAgo(9),
        amountMinor: 120000,
        currency: 'USD',
        payee: 'Freelance client',
        categoryId: 'cat-salary',
      ),
    ],
    trades: [
      Trade(
        id: 'trd-1',
        accountId: 'acc-broker',
        instrumentId: 'ins-etf',
        tradedOn: daysAgo(60),
        side: TradeSide.buy,
        units: Decimal.parse('2.5'),
        priceMinor: 11050,
        currency: 'EUR',
        feeMinor: 100,
      ),
      Trade(
        id: 'trd-2',
        accountId: 'acc-broker',
        instrumentId: 'ins-etf',
        tradedOn: daysAgo(18),
        side: TradeSide.buy,
        units: Decimal.parse('1.25'),
        priceMinor: 11800,
        currency: 'EUR',
        feeMinor: 100,
      ),
    ],
    prices: [
      Price(
        instrumentId: 'ins-etf',
        pricedOn: daysAgo(1),
        priceMinor: 12010,
        currency: 'EUR',
        provider: sampleProvider,
      ),
    ],
    fxRates: [
      // Cash flow converts each row on its own booking date, so a tracker needs
      // rates back through the reported period, not only a current one.
      FxRate(
        baseCurrency: 'EUR',
        quoteCurrency: 'USD',
        pricedOn: daysAgo(45),
        rate: Decimal.parse('1.07'),
        provider: sampleProvider,
      ),
      FxRate(
        baseCurrency: 'EUR',
        quoteCurrency: 'USD',
        pricedOn: daysAgo(1),
        rate: Decimal.parse('1.08'),
        provider: sampleProvider,
      ),
    ],
  );
}
