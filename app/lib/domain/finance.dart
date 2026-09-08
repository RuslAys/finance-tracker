/// Deterministic finance calculations over the canonical model.
///
/// This code is the authority for money. It reads canonical models only, never
/// spreadsheet cells, and no result here ever comes from an LLM.
library;

import 'dart:collection';

import 'decimal.dart';
import 'fx.dart';
import 'models.dart';

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
  static Map<String, Minor> accountBalances(
    TrackerDocument doc, {
    DateTime? asOf,
  }) {
    final balances = {for (final id in doc.accounts.keys) id: 0};
    for (final transaction in visibleTransactions(doc, asOf: asOf)) {
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
  static CashFlow cashFlow(
    TrackerDocument doc, {
    required String currency,
    DateTime? from,
    DateTime? to,
    FxConverter? fx,
  }) {
    final income = <String, Minor>{};
    final expense = <String, Minor>{};
    final unconverted = <String>{};
    for (final transaction in visibleTransactions(doc, asOf: to)) {
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
  static List<Holding> holdings(TrackerDocument doc, {DateTime? asOf}) {
    final books = <String, Queue<_Lot>>{};
    final realized = <String, Minor>{};

    final trades = doc.trades
        .where(
          (t) =>
              isCommitted(doc, t.importId) &&
              (asOf == null || !t.tradedOn.isAfter(asOf)),
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
  /// A trade and its settlement row, and the two legs of a transfer, may carry
  /// different dates. A valuation between them sees half the movement: the
  /// position and the cash that bought it at once, or money that has left one
  /// account and not yet arrived in the other. Each is wrong by the amount
  /// moved, and no correction is derivable — the other row simply is not
  /// recorded yet — so the valuation is unavailable on that date.
  static bool _movementsAreComplete(TrackerDocument doc, DateTime asOf) {
    final settled = <String>{};
    final transfersThrough = <String>{};
    final transfersAfter = <String>{};
    for (final transaction in doc.transactions) {
      if (!isCommitted(doc, transaction.importId)) continue;
      final through = !transaction.bookedOn.isAfter(asOf);
      final tradeId = transaction.tradeKey;
      if (tradeId != null && through) settled.add(tradeId);
      final transferId = transaction.transferKey;
      if (transferId != null) {
        (through ? transfersThrough : transfersAfter).add(transferId);
      }
    }
    if (transfersThrough.intersection(transfersAfter).isNotEmpty) return false;

    final executed = {
      for (final trade in doc.trades)
        if (isCommitted(doc, trade.importId) && !trade.tradedOn.isAfter(asOf))
          trade.id,
    };
    return settled.length == executed.length && settled.containsAll(executed);
  }
}
