/// Deterministic finance calculations over the canonical model.
///
/// This code is the authority for money. It reads canonical models only, never
/// spreadsheet cells, and no result here ever comes from an LLM.
library;

import 'dart:collection';

import 'decimal.dart';
import 'models.dart';

/// Thrown when the model cannot produce a defined result, such as a sell with
/// no matching FIFO lots.
class FinanceError implements Exception {
  FinanceError(this.message);

  final String message;

  @override
  String toString() => 'FinanceError: $message';
}

/// Income and expense of one currency over a period.
class CashFlow {
  const CashFlow(this.incomeByCategory, this.expenseByCategory);

  /// Signed sum per income category: a refund of income reduces it.
  final Map<String, Minor> incomeByCategory;

  /// Negated signed sum per expense category, so a refund reduces expense.
  final Map<String, Minor> expenseByCategory;

  Minor get totalIncome => incomeByCategory.values.fold(0, addMinor);

  Minor get totalExpense => expenseByCategory.values.fold(0, addMinor);

  Minor get net => subtractMinor(totalIncome, totalExpense);
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
  static bool _isCommitted(TrackerDocument doc, String importId) =>
      importId.isEmpty || doc.imports[importId] == ImportStatus.committed;

  static Iterable<Transaction> _visibleTransactions(TrackerDocument doc) =>
      doc.transactions.where((t) => _isCommitted(doc, t.importId));

  /// Balance per account, in that account's currency and minor units.
  ///
  /// Accounts without a visible transaction are reported as zero so the caller
  /// can render every account without a lookup fallback.
  static Map<String, Minor> accountBalances(TrackerDocument doc) {
    final balances = {for (final id in doc.accounts.keys) id: 0};
    for (final transaction in _visibleTransactions(doc)) {
      balances.update(
        transaction.accountId,
        (value) => addMinor(value, transaction.amountMinor),
        ifAbsent: () => transaction.amountMinor,
      );
    }
    return balances;
  }

  /// Cash flow of one currency between two dates, both inclusive.
  ///
  /// Transfers never appear: they move money between the user's own accounts.
  /// An uncategorized row is grouped under the empty key, on the side its sign
  /// implies.
  static CashFlow cashFlow(
    TrackerDocument doc, {
    required String currency,
    DateTime? from,
    DateTime? to,
  }) {
    final income = <String, Minor>{};
    final expense = <String, Minor>{};
    for (final transaction in _visibleTransactions(doc)) {
      if (transaction.currency != currency) continue;
      if (transaction.transferKey != null) continue;
      if (from != null && transaction.bookedOn.isBefore(from)) continue;
      if (to != null && transaction.bookedOn.isAfter(to)) continue;

      final categoryId = transaction.categoryKey;
      final type = categoryId == null
          ? null
          : doc.categories[categoryId]?.type;
      if (type == CategoryType.transfer) continue;

      final key = categoryId ?? '';
      final isIncome = type == null
          ? transaction.amountMinor >= 0
          : type == CategoryType.income;
      final target = isIncome ? income : expense;
      final signed = isIncome ? transaction.amountMinor : -transaction.amountMinor;
      target.update(key, (value) => addMinor(value, signed),
          ifAbsent: () => signed);
    }
    return CashFlow(income, expense);
  }

  /// FIFO holdings per `(account, instrument, currency)`.
  ///
  /// Buy fees are capitalized into lot cost; sell fees reduce proceeds. A sell
  /// larger than the available lots throws: v1 has no short positions.
  static List<Holding> holdings(TrackerDocument doc) {
    final books = <String, Queue<_Lot>>{};
    final realized = <String, Minor>{};

    final trades = doc.trades.where((t) => _isCommitted(doc, t.importId)).toList()
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
}
