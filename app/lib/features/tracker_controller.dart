/// State of the one open tracker.
///
/// The controller holds the canonical document and the results the deterministic
/// engine computed from it. Screens render these values; they never recompute
/// money themselves.
library;

import 'package:flutter/foundation.dart';

import '../domain/finance.dart';
import '../domain/fx.dart';
import '../domain/models.dart';
import '../domain/schema.dart';

class TrackerController extends ChangeNotifier {
  TrackerController(
    TrackerDocument document, {
    this.priceProvider = 'demo',
    this.rateProvider = 'demo',
    DateTime? asOf,
  }) : _document = document,
       asOf = asOf ?? todayUtc() {
    _recompute();
  }

  /// The date every price and rate lookup resolves against.
  final DateTime asOf;
  final String priceProvider;
  final String rateProvider;

  TrackerDocument _document;
  TrackerDocument get document => _document;

  late List<ValidationError> validationErrors;
  late List<Transaction> transactions;
  late FxConverter _fx;

  /// Empty when [financeError] is set; a screen then shows nothing rather than
  /// a zero it would have to explain away.
  late Map<String, Minor> balances;
  late CashFlow cashFlow;
  late List<Holding> holdings;
  late Minor? netWorthMinor;

  /// Set when the document cannot produce results, such as a sell without FIFO
  /// lots or an amount outside the exact minor-unit range. Screens show this
  /// instead of a wrong number.
  late String? financeError;

  void open(TrackerDocument document) {
    _document = document;
    _recompute();
    notifyListeners();
  }

  /// Recomputes once per opened document rather than once per widget build.
  void _recompute() {
    validationErrors = validateTracker(_document);
    transactions = FinanceEngine.visibleTransactions(_document).toList()
      ..sort((a, b) {
        final byDate = b.bookedOn.compareTo(a.bookedOn);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    _fx = FxConverter(_document, provider: rateProvider);
    balances = const {};
    cashFlow = const CashFlow({}, {});
    holdings = const [];
    netWorthMinor = null;
    financeError = null;

    // A document that failed validation can also fail arithmetic: an amount
    // outside the exact range throws RangeError, an unknown currency throws
    // ArgumentError. Catching every error keeps the validation report on screen
    // instead of taking the app down with it.
    try {
      balances = FinanceEngine.accountBalances(_document);
      cashFlow = FinanceEngine.cashFlow(
        _document,
        currency: _document.baseCurrency,
      );
      holdings = FinanceEngine.holdings(_document);
      netWorthMinor = FinanceEngine.netWorth(
        _document,
        priceProvider: priceProvider,
        rateProvider: rateProvider,
        asOf: asOf,
      );
    } catch (error) {
      balances = const {};
      cashFlow = const CashFlow({}, {});
      holdings = const [];
      netWorthMinor = null;
      financeError = error is FinanceError ? error.message : '$error';
    }
  }

  String get baseCurrency => _document.baseCurrency;

  /// Decimal places of a currency; an unknown code is a validation error, so
  /// the fallback only keeps a broken document renderable.
  int minorUnit(String currency) => _document.currencies[currency] ?? 2;

  /// Market value in the position's own settlement currency, so a screen can
  /// compare it with the FIFO cost. `null` when the position is unpriced or the
  /// quote currency cannot be converted.
  Minor? marketValue(Holding holding) {
    final value = FinanceEngine.marketValue(
      _document,
      holding,
      provider: priceProvider,
      asOf: asOf,
    );
    if (value == null) return null;
    return _fx.convertMinor(
      value.amount,
      from: value.currency,
      to: holding.currency,
      asOf: asOf,
    );
  }

  String accountName(String id) => _document.accounts[id]?.name ?? id;

  String instrumentName(String id) => _document.instruments[id]?.symbol ?? id;

  String categoryName(String? id) =>
      id == null ? 'Uncategorized' : _document.categories[id]?.name ?? id;
}

/// Today as a UTC date, matching the date-only values stored in a tracker.
DateTime todayUtc() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day);
}
