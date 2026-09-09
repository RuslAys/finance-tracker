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
    this.source = '',
    DateTime? asOf,
    DateTime? period,
  }) : _document = document,
       asOf = asOf ?? todayUtc(),
       _periodStart = monthStart(period ?? asOf ?? todayUtc()) {
    _recompute();
  }

  /// The valuation date: balances, positions, prices and rates all resolve on
  /// or before it, so every number on screen describes the same moment.
  final DateTime asOf;
  final String priceProvider;
  final String rateProvider;

  /// Workbook this document was read from; empty for the synthetic sample.
  /// The adapter is read-only, so nothing is ever written back to it.
  final String source;

  DateTime _periodStart;

  /// First day of the reported month, inclusive.
  DateTime get periodStart => _periodStart;

  /// Last day of the reported month, inclusive.
  DateTime get periodEnd => monthEnd(_periodStart);

  /// When the open results were last computed. Not a claim about how current
  /// the underlying records are: nothing here fetches from a bank.
  late DateTime refreshedAt;

  /// Reports the month containing [day]; the valuation date is unchanged.
  void selectMonth(DateTime day) {
    _periodStart = monthStart(day);
    _recompute();
    notifyListeners();
  }

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

  /// Named portfolios, then Unassigned. Empty when the tracker has no
  /// investment accounts.
  late List<PortfolioGroup> portfolioGroups;

  /// Investments of [portfolioId], or of every portfolio when it is null.
  late PortfolioReport portfolioReport;

  String? _portfolioId;

  /// The selected portfolio, or null for All portfolios.
  String? get portfolioId => _portfolioId;

  /// Reports one portfolio, or every one of them when [id] is null.
  void selectPortfolio(String? id) {
    _portfolioId = id;
    _recompute();
    notifyListeners();
  }

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
    refreshedAt = DateTime.now();
    validationErrors = validateTracker(_document);
    transactions =
        FinanceEngine.visibleTransactions(_document, asOf: asOf).toList()
      ..sort((a, b) {
        final byDate = b.bookedOn.compareTo(a.bookedOn);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    _fx = FxConverter(_document, provider: rateProvider);
    portfolioGroups = FinanceEngine.portfolioGroups(_document);
    // A portfolio that is gone from the reopened document cannot be reported;
    // fall back to All rather than showing another portfolio's numbers.
    if (!portfolioGroups.any((group) => group.id == _portfolioId)) {
      _portfolioId = null;
    }
    balances = const {};
    cashFlow = const CashFlow({}, {});
    holdings = const [];
    netWorthMinor = null;
    portfolioReport = _emptyPortfolioReport();
    financeError = null;

    // A document that failed validation can also fail arithmetic: an amount
    // outside the exact range throws RangeError, an unknown currency throws
    // ArgumentError. Catching every error keeps the validation report on screen
    // instead of taking the app down with it.
    try {
      balances = FinanceEngine.accountBalances(_document, asOf: asOf);
      cashFlow = FinanceEngine.cashFlow(
        _document,
        currency: _document.baseCurrency,
        from: periodStart,
        to: periodEnd,
        fx: _fx,
      );
      holdings = FinanceEngine.holdings(_document, asOf: asOf);
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

    // Computed apart from the totals above: the selected portfolio reads only
    // its own accounts, so an impossible sell or an unconvertible amount
    // somewhere else in the tracker must not take this report down with it.
    // The report itself withholds any total its own records cannot support.
    try {
      // The combined summary is computed from the union of the accounts, not by
      // adding up the per-portfolio reports.
      portfolioReport = FinanceEngine.portfolioReport(
        _document,
        accountIds: _scopeAccountIds(),
        currency: _document.baseCurrency,
        priceProvider: priceProvider,
        rateProvider: rateProvider,
        asOf: asOf,
      );
    } catch (error) {
      portfolioReport = _emptyPortfolioReport(
        error is FinanceError ? error.message : '$error',
      );
    }
  }

  /// The accounts of the selected portfolio, or of every portfolio.
  List<String> _scopeAccountIds() => [
    for (final group in portfolioGroups)
      if (_portfolioId == null || group.id == _portfolioId) ...group.accountIds,
  ];

  PortfolioReport _emptyPortfolioReport([
    String reason = 'No calculated results',
  ]) => PortfolioReport(
    accountIds: const [],
    currency: _document.baseCurrency,
    holdings: const [],
    cashMinor: null,
    valueMinor: null,
    costMinor: null,
    realizedGainMinor: null,
    unavailable: [reason],
  );

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

DateTime monthStart(DateTime day) => DateTime.utc(day.year, day.month, 1);

/// Day zero of the next month is the last day of this one, leap years included.
DateTime monthEnd(DateTime day) => DateTime.utc(day.year, day.month + 1, 0);
