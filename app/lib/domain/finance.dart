/// Deterministic finance calculations over the canonical model.
///
/// This code is the authority for money. It reads canonical models only, never
/// spreadsheet cells, and no result here ever comes from an LLM.
library;

import 'dart:collection';

import 'decimal.dart';
import 'fx.dart';
import 'models.dart';
import 'schema.dart';

/// Thrown when the model cannot produce a defined result, such as a sell with
/// no matching FIFO lots.
class FinanceError implements Exception {
  FinanceError(this.message);

  final String message;

  @override
  String toString() => 'FinanceError: $message';
}

/// Income and expense over a period, stated in one reporting currency.
class CashFlow {
  const CashFlow(
    this.incomeByCategory,
    this.expenseByCategory, {
    this.unconvertedCurrencies = const {},
  });

  /// Signed sum per income category: a refund of income reduces it.
  ///
  /// Partial while [unconvertedCurrencies] is non-empty: the rows that had no
  /// rate are missing from it. Only a complete report has totals.
  final Map<String, Minor> incomeByCategory;

  /// Negated signed sum per expense category, so a refund reduces expense.
  final Map<String, Minor> expenseByCategory;

  /// Currencies of included rows that had no rate to the reporting currency on
  /// their booking date. Reported so a screen can name what is missing.
  final Set<String> unconvertedCurrencies;

  /// False when a row of the period could not be converted, which makes every
  /// total unavailable rather than short by the rows that were dropped.
  bool get isComplete => unconvertedCurrencies.isEmpty;

  Minor? get totalIncome => isComplete ? _sum(incomeByCategory) : null;

  Minor? get totalExpense => isComplete ? _sum(expenseByCategory) : null;

  Minor? get net => isComplete
      ? subtractMinor(_sum(incomeByCategory), _sum(expenseByCategory))
      : null;

  static Minor _sum(Map<String, Minor> byCategory) =>
      byCategory.values.fold(0, addMinor);
}

/// Remaining position and realized result of one FIFO book.
class Holding {
  const Holding({
    required this.accountId,
    required this.instrumentId,
    required this.currency,
    required this.units,
    required this.costMinor,
    required this.realizedGainMinor,
  });

  final String accountId;
  final String instrumentId;
  final String currency;
  final Decimal units;

  /// FIFO cost of the remaining units, including capitalized buy fees.
  final Minor costMinor;
  final Minor realizedGainMinor;
}

/// The investment accounts reported under one portfolio.
///
/// Accounts without a portfolio are collected in the Unassigned group rather
/// than dropped, so All portfolios covers every investment account.
class PortfolioGroup {
  const PortfolioGroup({
    required this.id,
    required this.name,
    required this.accountIds,
  });

  /// Portfolio IDs are UUIDs, so the empty string cannot collide with one.
  static const String unassignedId = '';

  final String id;
  final String name;
  final List<String> accountIds;

  bool get isUnassigned => id == unassignedId;
}

/// One portfolio's investments on a valuation date, in one reporting currency.
///
/// Every total is nullable: a missing price, a missing rate, or a half-recorded
/// movement makes that total unavailable. None of them is ever reported as zero,
/// because a zero reads as a real amount.
class PortfolioReport {
  const PortfolioReport({
    required this.accountIds,
    required this.currency,
    required this.holdings,
    required this.cashMinor,
    required this.valueMinor,
    required this.costMinor,
    required this.realizedGainMinor,
    required this.unavailable,
  });

  /// The unique accounts this report covers, each counted exactly once.
  final List<String> accountIds;

  /// Currency of every converted total below.
  final String currency;

  /// FIFO books of the included accounts, in their own settlement currencies.
  final List<Holding> holdings;

  /// Account cash, kept apart from positions so a total that mixes the two is
  /// only ever shown under an explicit label.
  final Minor? cashMinor;

  /// Market value of the positions.
  final Minor? valueMinor;

  /// Remaining FIFO cost of the positions.
  final Minor? costMinor;
  final Minor? realizedGainMinor;

  /// Why a total is missing, in the words a screen can show. Empty when the
  /// report is complete.
  final List<String> unavailable;

  bool get isComplete => unavailable.isEmpty;

  Minor? get unrealizedGainMinor {
    final value = valueMinor;
    final cost = costMinor;
    return value == null || cost == null ? null : subtractMinor(value, cost);
  }

  /// Cash plus positions. A screen must label it as both; it is not the net
  /// worth of the tracker, which also counts accounts outside any portfolio.
  Minor? get totalMinor {
    final cash = cashMinor;
    final value = valueMinor;
    return cash == null || value == null ? null : addMinor(cash, value);
  }
}

class _Lot {
  _Lot(this.units, this.costMinor);

  Decimal units;
  Minor costMinor;
}

class FinanceEngine {
  const FinanceEngine._();

  /// Rows staged by a non-committed import are invisible to every calculation.
  ///
  /// A screen listing rows applies the same rule, so what a user sees always
  /// adds up to the balance shown next to it.
  static bool isCommitted(TrackerDocument doc, String importId) =>
      importId.isEmpty || doc.imports[importId] == ImportStatus.committed;

  /// The transactions every calculation and screen may show.
  ///
  /// [asOf] is a valuation date: a row booked after it did not exist yet, so a
  /// historical report must not see it. Every caller filters here, which keeps
  /// a listed row and the balance beside it computed from the same set.
  static Iterable<Transaction> visibleTransactions(
    TrackerDocument doc, {
    DateTime? asOf,
  }) => doc.transactions.where(
    (t) =>
        isCommitted(doc, t.importId) &&
        (asOf == null || !t.bookedOn.isAfter(asOf)),
  );

  /// Balance per account, in that account's currency and minor units, counting
  /// only rows booked through [asOf].
  ///
  /// Accounts without a visible transaction are reported as zero so the caller
  /// can render every account without a lookup fallback.
  ///
  /// With [accountIds], only those accounts are summed. Balances are per
  /// account, so this is the same result filtered — but it is filtered before
  /// the arithmetic, which keeps a sum that leaves the exact minor-unit range
  /// in one account from throwing out the balances of every other account.
  static Map<String, Minor> accountBalances(
    TrackerDocument doc, {
    DateTime? asOf,
    Set<String>? accountIds,
  }) {
    final balances = {
      for (final id in doc.accounts.keys)
        if (accountIds == null || accountIds.contains(id)) id: 0,
    };
    for (final transaction in visibleTransactions(doc, asOf: asOf)) {
      if (accountIds != null && !accountIds.contains(transaction.accountId)) {
        continue;
      }
      balances.update(
        transaction.accountId,
        (value) => addMinor(value, transaction.amountMinor),
        ifAbsent: () => transaction.amountMinor,
      );
    }
    return balances;
  }

  /// Cash flow in [currency] between two dates, both inclusive.
  ///
  /// Transfers never appear: they move money between the user's own accounts.
  /// Trade settlements never appear either, for the same reason: buying an
  /// asset moves cash into a position rather than spending it. Both still move
  /// the account balance. An uncategorized row is grouped under the empty key,
  /// on the side its sign implies.
  ///
  /// A row in another currency is converted with [fx] at its own booking date,
  /// which is the rate that applied when the money moved. Without [fx], or
  /// without a rate on that date, the row is not silently dropped: its currency
  /// is reported in `unconvertedCurrencies` and the totals become unavailable.
  ///
  /// With [accountIds], only rows booked in those accounts are counted, so a
  /// report scoped to some of the tracker's accounts states the flow of those
  /// accounts rather than of every account the tracker holds.
  static CashFlow cashFlow(
    TrackerDocument doc, {
    required String currency,
    DateTime? from,
    DateTime? to,
    FxConverter? fx,
    Set<String>? accountIds,
  }) {
    final income = <String, Minor>{};
    final expense = <String, Minor>{};
    final unconverted = <String>{};
    for (final transaction in visibleTransactions(doc, asOf: to)) {
      if (accountIds != null && !accountIds.contains(transaction.accountId)) {
        continue;
      }
      if (transaction.transferKey != null) continue;
      if (transaction.tradeKey != null) continue;
      if (from != null && transaction.bookedOn.isBefore(from)) continue;

      final categoryId = transaction.categoryKey;
      final type = categoryId == null
          ? null
          : doc.categories[categoryId]?.type;
      if (type == CategoryType.transfer) continue;

      var amount = transaction.amountMinor;
      if (transaction.currency != currency) {
        final converted = fx?.convertMinor(
          amount,
          from: transaction.currency,
          to: currency,
          asOf: transaction.bookedOn,
        );
        if (converted == null) {
          unconverted.add(transaction.currency);
          continue;
        }
        amount = converted;
      }

      final key = categoryId ?? '';
      final isIncome = type == null
          ? transaction.amountMinor >= 0
          : type == CategoryType.income;
      final target = isIncome ? income : expense;
      final signed = isIncome ? amount : -amount;
      target.update(key, (value) => addMinor(value, signed),
          ifAbsent: () => signed);
    }
    return CashFlow(income, expense, unconvertedCurrencies: unconverted);
  }

  /// FIFO holdings per `(account, instrument, currency)`, from trades executed
  /// through [asOf].
  ///
  /// Buy fees are capitalized into lot cost; sell fees reduce proceeds. A sell
  /// larger than the available lots throws: v1 has no short positions.
  ///
  /// With [accountIds], only those accounts' trades are read. A book belongs to
  /// one account, so this is the same result filtered — but it is filtered
  /// before the arithmetic, which keeps one account's impossible sell from
  /// throwing out the holdings of every other account in the tracker.
  static List<Holding> holdings(
    TrackerDocument doc, {
    DateTime? asOf,
    Set<String>? accountIds,
  }) {
    final books = <String, Queue<_Lot>>{};
    final realized = <String, Minor>{};

    final trades = doc.trades
        .where(
          (t) =>
              isCommitted(doc, t.importId) &&
              (asOf == null || !t.tradedOn.isAfter(asOf)) &&
              (accountIds == null || accountIds.contains(t.accountId)),
        )
        .toList()
      ..sort((a, b) {
        final byDate = a.tradedOn.compareTo(b.tradedOn);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    for (final trade in trades) {
      final key = '${trade.accountId}|${trade.instrumentId}|${trade.currency}';
      final lots = books.putIfAbsent(key, Queue<_Lot>.new);
      final notional = trade.units.timesInt(trade.priceMinor).roundToMinor();

      if (trade.side == TradeSide.buy) {
        lots.add(_Lot(trade.units, addMinor(notional, trade.feeMinor)));
        continue;
      }

      var remaining = trade.units;
      var cost = 0;
      while (remaining > Decimal.zero) {
        if (lots.isEmpty) {
          throw FinanceError(
            'Trade ${trade.id} sells more units than the FIFO lots hold',
          );
        }
        final lot = lots.first;
        if (lot.units <= remaining) {
          cost = addMinor(cost, lot.costMinor);
          remaining = remaining - lot.units;
          lots.removeFirst();
          continue;
        }
        // Split the lot by remaining cost, so repeated partial sells cannot
        // drift away from the lot's original total.
        final part = remaining.proportionOf(lot.costMinor, lot.units);
        cost = addMinor(cost, part);
        lot.costMinor = subtractMinor(lot.costMinor, part);
        lot.units = lot.units - remaining;
        remaining = Decimal.zero;
      }
      final gain = subtractMinor(subtractMinor(notional, trade.feeMinor), cost);
      realized.update(key, (value) => addMinor(value, gain), ifAbsent: () => gain);
    }

    final result = <Holding>[];
    for (final key in books.keys.toList()..sort()) {
      final parts = key.split('|');
      final lots = books[key]!;
      result.add(
        Holding(
          accountId: parts[0],
          instrumentId: parts[1],
          currency: parts[2],
          units: lots.fold(Decimal.zero, (sum, lot) => sum + lot.units),
          costMinor: lots.fold(0, (sum, lot) => addMinor(sum, lot.costMinor)),
          realizedGainMinor: realized[key] ?? 0,
        ),
      );
    }
    return result;
  }

  /// Latest stored price of an instrument on or before [asOf], in one currency
  /// from one provider. Returns `null` when that provider has priced nothing.
  ///
  /// A row the schema rejects is not an observation: selecting a negative or
  /// inexact price would value a real position at a negative amount, which
  /// reads as a loss rather than as the broken row it is.
  // ponytail: linear scan; index by instrument if price history gets large.
  static Minor? priceAt(
    TrackerDocument doc,
    String instrumentId, {
    required String currency,
    required String provider,
    required DateTime asOf,
  }) {
    Price? best;
    for (final price in doc.prices) {
      if (price.instrumentId != instrumentId) continue;
      if (price.currency != currency || price.provider != provider) continue;
      if (price.pricedOn.isAfter(asOf)) continue;
      if (price.priceMinor < 0 || !isExactMinor(price.priceMinor)) continue;
      if (best == null || price.pricedOn.isAfter(best.pricedOn)) best = price;
    }
    return best?.priceMinor;
  }

  /// Market value of a holding: units × the latest price, rounded once, in the
  /// currency that price was quoted in.
  ///
  /// An instrument's reference currency may differ from the settlement currency
  /// of the trades that built the position, so a quote in either one values it.
  /// The settlement currency wins when both exist, because it needs no rate.
  /// Returns `null` when the position has no price on or before [asOf]; an
  /// unpriced position is unavailable, never zero.
  static ({Minor amount, String currency})? marketValue(
    TrackerDocument doc,
    Holding holding, {
    required String provider,
    required DateTime asOf,
  }) {
    // A fully sold book stays in [holdings] to carry its realized gain. It
    // holds nothing, so it is worth zero at any price: requiring a current
    // quote for it would make a portfolio that closed a position unavailable.
    if (holding.units == Decimal.zero) {
      return (amount: 0, currency: holding.currency);
    }
    for (final currency in {
      holding.currency,
      ?doc.instruments[holding.instrumentId]?.currency,
    }) {
      final price = priceAt(
        doc,
        holding.instrumentId,
        currency: currency,
        provider: provider,
        asOf: asOf,
      );
      if (price != null) {
        return (
          amount: holding.units.timesInt(price).roundToMinor(),
          currency: currency,
        );
      }
    }
    return null;
  }

  /// Investment accounts grouped by portfolio, named portfolios first in name
  /// order, then Unassigned when any investment account has no portfolio.
  ///
  /// An account belongs to at most one portfolio, so the groups never overlap
  /// and their accounts can be unioned without counting one twice. A portfolio
  /// with no accounts is still listed: the user created it.
  static List<PortfolioGroup> portfolioGroups(TrackerDocument doc) {
    final byPortfolio = <String, List<String>>{
      for (final portfolio in doc.portfolios.keys) portfolio: [],
    };
    final unassigned = <String>[];
    for (final account in doc.accounts.values) {
      if (!account.isInvestment) continue;
      final portfolioId = account.portfolioKey;
      // An unknown reference is a validation error; the account is reported as
      // unassigned rather than hidden from every portfolio view.
      final target = portfolioId == null ? null : byPortfolio[portfolioId];
      (target ?? unassigned).add(account.id);
    }

    final groups = [
      for (final portfolio in doc.portfolios.values)
        PortfolioGroup(
          id: portfolio.id,
          name: portfolio.name,
          accountIds: byPortfolio[portfolio.id]!..sort(),
        ),
    ]..sort((a, b) {
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    if (unassigned.isNotEmpty) {
      groups.add(
        PortfolioGroup(
          id: PortfolioGroup.unassignedId,
          name: 'Unassigned',
          accountIds: unassigned..sort(),
        ),
      );
    }
    return groups;
  }

  /// The investments of [accountIds] on [asOf], stated in [currency].
  ///
  /// Callers pass account IDs, not sub-reports: a combined summary is computed
  /// from the union of the accounts, never by adding the totals of separate
  /// portfolio reports, which would double count any account reachable twice.
  ///
  /// Cash and positions convert at the valuation date, which is the rate that
  /// values them on that date. Cost and realized gains do not: they accumulated
  /// on the dates their trades executed, and no historical conversion policy is
  /// defined yet, so they are reported only while every included position
  /// already settles in [currency].
  static PortfolioReport portfolioReport(
    TrackerDocument doc, {
    required Iterable<String> accountIds,
    required String currency,
    required String priceProvider,
    required String rateProvider,
    required DateTime asOf,
  }) {
    final ids = accountIds.toSet();
    final unavailable = <String>[];
    final fx = FxConverter(doc, provider: rateProvider);

    // An impossible sell in another portfolio is that portfolio's problem: this
    // one reports, and only a sell inside it makes it unavailable.
    var positions = const <Holding>[];
    var booksAreSound = true;
    try {
      positions = holdings(doc, asOf: asOf, accountIds: ids);
    } on FinanceError catch (error) {
      booksAreSound = false;
      unavailable.add(error.message);
    }

    // The same rule net worth applies, narrowed to these accounts: half a trade
    // or half a transfer values the position and the cash that bought it at
    // once. A movement elsewhere in the tracker is another report's problem.
    final movementsComplete = _movementsAreComplete(doc, asOf, accountIds: ids);
    if (!movementsComplete) {
      unavailable.add('A trade or transfer is only half recorded on ${formatIsoDate(asOf)}');
    }

    // The currencies this report reads, and the subset it has to convert. A
    // report that converts nothing depends on no rate at all.
    final used = {currency, for (final holding in positions) holding.currency};
    final convertedFrom = <String>{};

    final unpriced = <String>{};
    final unconvertedPositions = <String>{};
    var value = 0;
    for (final holding in positions) {
      final quote = marketValue(
        doc,
        holding,
        provider: priceProvider,
        asOf: asOf,
      );
      if (quote == null) {
        unpriced.add(holding.instrumentId);
        continue;
      }
      used.add(quote.currency);
      // Recorded whether or not the conversion succeeds: a failure may be the
      // broken row's doing, and naming it is the point.
      if (quote.currency != currency && quote.amount != 0) {
        convertedFrom.add(quote.currency);
      }
      final converted = fx.convertMinor(
        quote.amount,
        from: quote.currency,
        to: currency,
        asOf: asOf,
      );
      if (converted == null) {
        unconvertedPositions.add(quote.currency);
        continue;
      }
      value = addMinor(value, converted);
    }

    final unconvertedCash = <String>{};
    final balances = accountBalances(doc, asOf: asOf, accountIds: ids);
    var cash = 0;
    var cashKnown = true;
    for (final id in ids) {
      final account = doc.accounts[id];
      if (account == null) {
        cashKnown = false;
        unavailable.add('Unknown account $id');
        continue;
      }
      final balance = balances[id] ?? 0;
      used.add(account.currency);
      if (account.currency != currency && balance != 0) {
        convertedFrom.add(account.currency);
      }
      final converted = fx.convertMinor(
        balance,
        from: account.currency,
        to: currency,
        asOf: asOf,
      );
      if (converted == null) {
        cashKnown = false;
        unconvertedCash.add(account.currency);
        continue;
      }
      cash = addMinor(cash, converted);
    }

    final foreignBooks = {
      for (final holding in positions)
        if (holding.currency != currency) holding.currency,
    };
    if (foreignBooks.isNotEmpty) {
      unavailable.add(
        'Cost and realized gains in ${_list(foreignBooks)} need a historical '
        'conversion policy to $currency',
      );
    }
    if (unpriced.isNotEmpty) {
      unavailable.add('No price for ${_list(unpriced)} on ${formatIsoDate(asOf)}');
    }
    for (final missing in {...unconvertedPositions, ...unconvertedCash}) {
      unavailable.add('No rate from $missing to $currency on ${formatIsoDate(asOf)}');
    }

    // The quotes `marketValue` would look for: a position's own settlement
    // currency, then its instrument's reference currency. A price in any other
    // currency is one this report never reads, and a closed book reads none at
    // all: it is worth zero whatever its instrument is quoted at.
    final quotes = <String, Set<String>>{};
    for (final holding in positions) {
      if (holding.units == Decimal.zero) continue;
      quotes
          .putIfAbsent(holding.instrumentId, () => {})
          .addAll({
            holding.currency,
            ?doc.instruments[holding.instrumentId]?.currency,
          });
    }

    final invalid = scopedErrors(
      doc,
      ids,
      quoteCurrencies: quotes,
      currencies: used,
      // A leg is always drawn between two of these: the pair being converted,
      // or one of them and the base currency it triangulates through.
      fxCurrencies: convertedFrom.isEmpty
          ? const {}
          : {...convertedFrom, currency, doc.baseCurrency},
      priceProvider: priceProvider,
      rateProvider: rateProvider,
      asOf: asOf,
    );
    unavailable.addAll(invalid.map((error) => '$error'));
    final usable = movementsComplete && booksAreSound && invalid.isEmpty;

    final booksConvert = foreignBooks.isEmpty;
    return PortfolioReport(
      accountIds: ids.toList()..sort(),
      currency: currency,
      holdings: positions,
      cashMinor: usable && cashKnown ? cash : null,
      valueMinor:
          usable && unpriced.isEmpty && unconvertedPositions.isEmpty
          ? value
          : null,
      costMinor: usable && booksConvert
          ? positions.fold<Minor>(0, (sum, h) => addMinor(sum, h.costMinor))
          : null,
      realizedGainMinor: usable && booksConvert
          ? positions.fold<Minor>(0, (sum, h) => addMinor(sum, h.realizedGainMinor))
          : null,
      unavailable: unavailable,
    );
  }

  static String _list(Iterable<String> values) =>
      (values.toList()..sort()).join(', ');

  /// Validation errors of the records [accountIds] reports on, valued with the
  /// prices of [quoteCurrencies]: the currencies each held instrument may be
  /// quoted in for this report.
  ///
  /// [_movementsAreComplete] only compares ids and dates. A trade whose
  /// settlement row names the wrong account or a different amount passes it and
  /// would combine a real FIFO position with cash that never moved that way, so
  /// the report has to withhold its totals rather than look complete. Errors of
  /// records outside these accounts are somebody else's report to withhold.
  /// A snapshot leaving the app scopes its completeness markers through here
  /// too, so a caller approved for some accounts learns nothing about the rest.
  // ponytail: revalidates the whole document per report; pass the caller's
  // errors in if reports ever run per widget rather than per opened tracker.
  static List<ValidationError> scopedErrors(
    TrackerDocument doc,
    Set<String> accountIds, {
    required Map<String, Set<String>> quoteCurrencies,
    required Set<String> currencies,
    required Set<String> fxCurrencies,
    required String priceProvider,
    required String rateProvider,
    required DateTime asOf,
  }) {
    // A validation error names the row it is about: an account, a trade, a
    // transaction, or the transfer id shared by two of them.
    final accountsOf = <String, Set<String>>{};
    void link(String key, String accountId) =>
        accountsOf.putIfAbsent(key, () => {}).add(accountId);
    for (final id in accountIds) {
      link(id, id);
    }
    for (final trade in doc.trades) {
      link(trade.id, trade.accountId);
    }
    for (final transaction in doc.transactions) {
      link(transaction.id, transaction.accountId);
      final transferId = transaction.transferKey;
      if (transferId != null) link(transferId, transaction.accountId);
      // A settlement row in one of these accounts pins its trade here too.
      final tradeId = transaction.tradeKey;
      if (tradeId != null) link(tradeId, transaction.accountId);
    }

    return [
      for (final error in validateTracker(doc))
        if (switch (error.entity) {
          // The base currency every conversion may triangulate through.
          '_meta' => true,
          'currencies' => currencies.contains(error.id),
          // `(instrument_id, priced_on, currency, provider)`. Another
          // provider's row, or one dated after the valuation, is never the
          // observation this report reads.
          'prices' => _keyed(error.id, 4, (parts) =>
              (quoteCurrencies[parts[0]] ?? const <String>{}).contains(
                parts[2],
              ) &&
              parts[3] == priceProvider &&
              !_isoAfter(parts[1], asOf)),
          'instruments' => quoteCurrencies.containsKey(error.id),
          // `(base_currency, quote_currency, priced_on, provider)`. Both sides
          // of a leg are currencies this report converts between, so a pair
          // touching neither cannot be selected for it.
          'fx_rates' => _keyed(error.id, 4, (parts) =>
              fxCurrencies.contains(parts[0]) &&
              fxCurrencies.contains(parts[1]) &&
              parts[3] == rateProvider &&
              !_isoAfter(parts[2], asOf)),
          _ => (accountsOf[error.id] ?? const <String>{}).any(
            accountIds.contains,
          ),
        })
          error,
    ];
  }

  /// Applies [test] to a composite key's fields, or reports the row as relevant
  /// when the key does not have the expected shape: an error nobody can place
  /// is withheld rather than dropped.
  static bool _keyed(String id, int fields, bool Function(List<String>) test) {
    final parts = id.split('|');
    return parts.length != fields || test(parts);
  }

  /// Whether an ISO date field of a composite key is after [asOf]. An
  /// unparsable one counts as relevant, for the same reason.
  static bool _isoAfter(String value, DateTime asOf) {
    try {
      return parseIsoDate(value).isAfter(asOf);
    } on FormatException {
      return false;
    }
  }

  /// Cash balances plus priced positions on [asOf], converted to the base
  /// currency.
  ///
  /// [asOf] is the valuation date of the whole total: transactions and trades
  /// after it are excluded, and prices and rates resolve on or before it. A
  /// past date therefore reports what the tracker was worth then.
  ///
  /// A trade's settlement cash movement is a stored `transactions` row, never
  /// derived from the trade, so the two terms do not overlap. A tracker that
  /// omits those rows overstates this total; see `docs/spreadsheet-format.md`.
  ///
  /// Returns `null` as soon as one rate or price is missing, or a movement is
  /// only half recorded on [asOf]: a total that silently dropped a position,
  /// counted its cash twice, or lost money in transit between two accounts
  /// would read as a real net worth.
  static Minor? netWorth(
    TrackerDocument doc, {
    required String priceProvider,
    required String rateProvider,
    required DateTime asOf,
  }) {
    if (!_movementsAreComplete(doc, asOf)) return null;

    final fx = FxConverter(doc, provider: rateProvider);
    var total = 0;

    Minor? toBase(Minor amount, String currency) => fx.convertMinor(
      amount,
      from: currency,
      to: doc.baseCurrency,
      asOf: asOf,
    );

    for (final entry in accountBalances(doc, asOf: asOf).entries) {
      final currency = doc.accounts[entry.key]?.currency;
      if (currency == null) return null;
      final converted = toBase(entry.value, currency);
      if (converted == null) return null;
      total = addMinor(total, converted);
    }
    for (final holding in holdings(doc, asOf: asOf)) {
      final value = marketValue(
        doc,
        holding,
        provider: priceProvider,
        asOf: asOf,
      );
      if (value == null) return null;
      final converted = toBase(value.amount, value.currency);
      if (converted == null) return null;
      total = addMinor(total, converted);
    }
    return total;
  }

  /// Whether every movement recorded in more than one row has all of its rows
  /// on the same side of [asOf].
  ///
  /// With [accountIds], only the movements of those accounts are checked, plus
  /// any transfer with a leg in them: money crossing that boundary is in
  /// transit for this report even when its other account is outside it. A
  /// movement between two accounts nobody selected changes nothing here.
  ///
  /// A trade and its settlement row, and the two legs of a transfer, may carry
  /// different dates. A valuation between them sees half the movement: the
  /// position and the cash that bought it at once, or money that has left one
  /// account and not yet arrived in the other. Each is wrong by the amount
  /// moved, and no correction is derivable — the other row simply is not
  /// recorded yet — so the valuation is unavailable on that date.
  static bool _movementsAreComplete(
    TrackerDocument doc,
    DateTime asOf, {
    Set<String>? accountIds,
  }) {
    bool inScope(String accountId) =>
        accountIds == null || accountIds.contains(accountId);

    final scopedTransfers = <String>{};
    for (final transaction in doc.transactions) {
      if (!isCommitted(doc, transaction.importId)) continue;
      final transferId = transaction.transferKey;
      if (transferId != null && inScope(transaction.accountId)) {
        scopedTransfers.add(transferId);
      }
    }

    final settled = <String>{};
    final transfersThrough = <String>{};
    final transfersAfter = <String>{};
    for (final transaction in doc.transactions) {
      if (!isCommitted(doc, transaction.importId)) continue;
      final through = !transaction.bookedOn.isAfter(asOf);
      final tradeId = transaction.tradeKey;
      if (tradeId != null && through && inScope(transaction.accountId)) {
        settled.add(tradeId);
      }
      final transferId = transaction.transferKey;
      // Both legs of a scoped transfer count, including the one outside it.
      if (transferId != null && scopedTransfers.contains(transferId)) {
        (through ? transfersThrough : transfersAfter).add(transferId);
      }
    }
    if (transfersThrough.intersection(transfersAfter).isNotEmpty) return false;

    final executed = {
      for (final trade in doc.trades)
        if (isCommitted(doc, trade.importId) &&
            !trade.tradedOn.isAfter(asOf) &&
            inScope(trade.accountId))
          trade.id,
    };
    return settled.length == executed.length && settled.containsAll(executed);
  }
}
