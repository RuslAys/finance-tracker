/// The canonical tracker model.
///
/// This is the only shape that crosses a boundary: storage adapters map a
/// workbook or Google Sheet into it, and the finance engine reads nothing else.
/// Field meanings are defined by `docs/spreadsheet-format.md`.
library;

import 'decimal.dart';

/// Money is always integer minor units, scaled by `currencies.minor_unit`.
typedef Minor = int;

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Parses a `YYYY-MM-DD` tracker date. Any other form is a validation error.
DateTime parseIsoDate(String value) {
  if (!_isoDate.hasMatch(value)) {
    throw FormatException('Not a YYYY-MM-DD date', value);
  }
  final parsed = DateTime.parse('${value}T00:00:00Z');
  if (formatIsoDate(parsed) != value) {
    throw FormatException('Not a real calendar date', value);
  }
  return parsed;
}

/// Writes a tracker date back as `YYYY-MM-DD`.
String formatIsoDate(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);

enum CategoryType { income, expense, transfer }

enum TradeSide { buy, sell }

enum ImportStatus { pending, committed, failed, cancelled }

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.archived = false,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
  final bool archived;
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String? parentId;
}

class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.bookedOn,
    required this.amountMinor,
    required this.currency,
    this.payee = '',
    this.description = '',
    this.categoryId,
    this.transferId,
    this.tradeId,
    this.source = 'manual',
    this.sourceId = '',
    this.rowFingerprint = '',
    this.importId = '',
    this.createdAt,
  });

  final String id;
  final String accountId;
  final DateTime bookedOn;

  /// Positive when money enters the account, negative when it leaves.
  final Minor amountMinor;
  final String currency;
  final String payee;
  final String description;
  final String? categoryId;
  final String? transferId;

  /// Set on the one row that settles a trade's cash; blank on a cash row.
  final String? tradeId;
  final String source;
  final String sourceId;
  final String rowFingerprint;

  /// Empty for a manual row; otherwise the `imports.id` that staged it.
  final String importId;
  final DateTime? createdAt;

  /// A mapper may render an empty cell as `null` or `''`; both mean absent.
  String? get transferKey => _blankToNull(transferId);

  String? get categoryKey => _blankToNull(categoryId);

  String? get tradeKey => _blankToNull(tradeId);
}

String? _blankToNull(String? value) =>
    value == null || value.isEmpty ? null : value;

class Instrument {
  const Instrument({
    required this.id,
    required this.symbol,
    required this.name,
    required this.type,
    required this.currency,
  });

  final String id;
  final String symbol;
  final String name;
  final String type;

  /// Reference currency of the instrument; a trade settles in its own currency.
  final String currency;
}

class Trade {
  const Trade({
    required this.id,
    required this.accountId,
    required this.instrumentId,
    required this.tradedOn,
    required this.side,
    required this.units,
    required this.priceMinor,
    required this.currency,
    this.feeMinor = 0,
    this.source = 'manual',
    this.sourceId = '',
    this.rowFingerprint = '',
    this.importId = '',
  });

  final String id;
  final String accountId;
  final String instrumentId;
  final DateTime tradedOn;
  final TradeSide side;

  /// Always positive; short positions are not supported in v1.
  final Decimal units;
  final Minor priceMinor;

  /// Settlement currency, which must equal the account currency.
  final String currency;
  final Minor feeMinor;
  final String source;
  final String sourceId;
  final String rowFingerprint;
  final String importId;
}

class Price {
  const Price({
    required this.instrumentId,
    required this.pricedOn,
    required this.priceMinor,
    required this.currency,
    required this.provider,
  });

  final String instrumentId;
  final DateTime pricedOn;
  final Minor priceMinor;
  final String currency;

  /// Price source; a report never mixes providers.
  final String provider;
}

class FxRate {
  const FxRate({
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.pricedOn,
    required this.rate,
    required this.provider,
  });

  final String baseCurrency;
  final String quoteCurrency;
  final DateTime pricedOn;

  /// Quote-currency units per one base-currency unit, as an exact decimal.
  final Decimal rate;
  final String provider;
}

class TrackerDocument {
  const TrackerDocument({
    required this.trackerId,
    required this.baseCurrency,
    required this.currencies,
    this.accounts = const {},
    this.categories = const {},
    this.instruments = const {},
    this.transactions = const [],
    this.trades = const [],
    this.prices = const [],
    this.fxRates = const [],
    this.imports = const {},
  });

  final String trackerId;
  final String baseCurrency;

  /// Currency code to `minor_unit` exponent, such as `EUR` to `2`.
  final Map<String, int> currencies;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;
  final Map<String, Instrument> instruments;
  final List<Transaction> transactions;
  final List<Trade> trades;
  final List<Price> prices;
  final List<FxRate> fxRates;

  /// Status of every `imports` row; rows of a non-committed import are excluded
  /// from every calculation until that import commits.
  final Map<String, ImportStatus> imports;
}
