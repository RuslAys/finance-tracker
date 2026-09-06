/// Canonical schema validation.
///
/// A storage adapter runs this after mapping a workbook or Sheet and before the
/// finance engine sees the document. The rules come from
/// `docs/spreadsheet-format.md`; anything that cannot be interpreted exactly is
/// reported, never silently rewritten.
library;

import 'decimal.dart';
import 'models.dart';

class ValidationError {
  const ValidationError(this.entity, this.id, this.message);

  /// Canonical tab name, such as `transactions`.
  final String entity;

  /// Row id, or the referencing key when the row itself has none.
  final String id;
  final String message;

  @override
  String toString() => '$entity[$id]: $message';
}

/// Validates the whole document and returns every problem found.
List<ValidationError> validateTracker(TrackerDocument doc) {
  final errors = <ValidationError>[];

  void check(bool ok, String entity, String id, String message) {
    if (!ok) errors.add(ValidationError(entity, id, message));
  }

  check(
    doc.currencies.containsKey(doc.baseCurrency),
    '_meta',
    'base_currency',
    'Currency ${doc.baseCurrency} has no currencies row',
  );
  doc.currencies.forEach((code, minorUnit) {
    check(minorUnit >= 0, 'currencies', code, 'minor_unit must not be negative');
  });

  for (final account in doc.accounts.values) {
    check(
      doc.currencies.containsKey(account.currency),
      'accounts',
      account.id,
      'Currency ${account.currency} has no currencies row',
    );
  }
  for (final instrument in doc.instruments.values) {
    // Without its currencies row, a later price cannot be scaled to minor units.
    check(
      doc.currencies.containsKey(instrument.currency),
      'instruments',
      instrument.id,
      'Currency ${instrument.currency} has no currencies row',
    );
  }

  _validateCategories(doc, check);
  _validateTransactions(doc, check);
  _validateTrades(doc, check);
  _validateTradeSettlements(doc, check);
  _validatePrices(doc, check);
  _validateFxRates(doc, check);

  return errors;
}

typedef _Check = void Function(bool ok, String entity, String id, String message);

void _validateCategories(TrackerDocument doc, _Check check) {
  for (final category in doc.categories.values) {
    final parentId = category.parentId;
    if (parentId == null || parentId.isEmpty) continue;
    final parent = doc.categories[parentId];
    if (parent == null) {
      check(false, 'categories', category.id, 'Unknown parent_id $parentId');
      continue;
    }
    check(
      parent.type == category.type,
      'categories',
      category.id,
      'Parent type ${parent.type.name} differs from ${category.type.name}',
    );

    // Walk to the root; a cycle is bounded by the number of categories.
    final seen = <String>{category.id};
    var current = parent;
    while (true) {
      if (!seen.add(current.id)) {
        check(false, 'categories', category.id, 'Parent links form a cycle');
        break;
      }
      final next = current.parentId;
      if (next == null || next.isEmpty) break;
      final nextCategory = doc.categories[next];
      if (nextCategory == null) break;
      current = nextCategory;
    }
  }
}

/// The unique bank identity of an imported row, when the bank supplies one.
String _bankIdentity(String accountId, String source, String sourceId) =>
    '$accountId|$source|$sourceId';

void _validateTransactions(TrackerDocument doc, _Check check) {
  final ids = <String>{};
  final identities = <String>{};
  final transfers = <String, List<Transaction>>{};

  for (final transaction in doc.transactions) {
    check(ids.add(transaction.id), 'transactions', transaction.id, 'Duplicate id');

    if (transaction.sourceId.isNotEmpty) {
      check(
        identities.add(_bankIdentity(transaction.accountId, transaction.source,
            transaction.sourceId)),
        'transactions',
        transaction.id,
        'Duplicate bank identity (account_id, source, source_id)',
      );
    }

    // A balance returns a single amount unchanged, so an unsafe stored value
    // would reach a report without passing any arithmetic guard.
    check(isExactMinor(transaction.amountMinor), 'transactions', transaction.id,
        'amount_minor is outside the exact minor-unit range');

    final account = doc.accounts[transaction.accountId];
    if (account == null) {
      check(false, 'transactions', transaction.id,
          'Unknown account_id ${transaction.accountId}');
    } else {
      check(
        transaction.currency == account.currency,
        'transactions',
        transaction.id,
        'Currency ${transaction.currency} differs from account currency '
            '${account.currency}',
      );
    }

    final categoryId = transaction.categoryKey;
    if (categoryId != null) {
      final category = doc.categories[categoryId];
      check(category != null, 'transactions', transaction.id,
          'Unknown category_id $categoryId');
      // Cash flow hides both sides of a transfer, so a transfer row without its
      // pair would vanish from every report instead of balancing one.
      check(
        category?.type != CategoryType.transfer ||
            transaction.transferKey != null,
        'transactions',
        transaction.id,
        'Transfer category needs a transfer_id',
      );
    }
    if (transaction.importId.isNotEmpty) {
      check(doc.imports.containsKey(transaction.importId), 'transactions',
          transaction.id, 'Unknown import_id ${transaction.importId}');
    }

    final transferId = transaction.transferKey;
    if (transferId != null) {
      transfers.putIfAbsent(transferId, () => []).add(transaction);
    }
  }

  transfers.forEach((transferId, legs) {
    if (legs.length != 2) {
      check(false, 'transactions', transferId,
          'transfer_id has ${legs.length} legs, expected 2');
      return;
    }
    final [first, second] = legs;
    check(first.accountId != second.accountId, 'transactions', transferId,
        'Both transfer legs are in the same account');
    check(first.currency == second.currency, 'transactions', transferId,
        'Transfer legs use different currencies; v1 has no cross-currency transfer');
    check(first.amountMinor + second.amountMinor == 0, 'transactions',
        transferId, 'Transfer legs do not sum to zero');
    for (final leg in legs) {
      // Cash flow hides every row carrying a transfer_id, so an accidental id on
      // an ordinary row would silently shrink a report. Require the category
      // that makes the row a real transfer.
      final categoryId = leg.categoryKey;
      final type = categoryId == null ? null : doc.categories[categoryId]?.type;
      check(type == CategoryType.transfer, 'transactions', leg.id,
          'Transfer leg needs a transfer category');
    }
  });
}

void _validateTrades(TrackerDocument doc, _Check check) {
  final ids = <String>{};
  final identities = <String>{};
  for (final trade in doc.trades) {
    check(ids.add(trade.id), 'trades', trade.id, 'Duplicate id');

    if (trade.sourceId.isNotEmpty) {
      check(
        identities
            .add(_bankIdentity(trade.accountId, trade.source, trade.sourceId)),
        'trades',
        trade.id,
        'Duplicate bank identity (account_id, source, source_id)',
      );
    }

    final account = doc.accounts[trade.accountId];
    if (account == null) {
      check(false, 'trades', trade.id, 'Unknown account_id ${trade.accountId}');
    } else {
      check(
        trade.currency == account.currency,
        'trades',
        trade.id,
        'Settlement currency ${trade.currency} differs from account currency '
            '${account.currency}',
      );
    }
    check(doc.instruments.containsKey(trade.instrumentId), 'trades', trade.id,
        'Unknown instrument_id ${trade.instrumentId}');
    check(trade.units > Decimal.zero, 'trades', trade.id,
        'units must be positive');
    check(trade.priceMinor >= 0, 'trades', trade.id,
        'price_minor must not be negative');
    check(trade.feeMinor >= 0, 'trades', trade.id,
        'fee_minor must not be negative');
    check(isExactMinor(trade.priceMinor), 'trades', trade.id,
        'price_minor is outside the exact minor-unit range');
    check(isExactMinor(trade.feeMinor), 'trades', trade.id,
        'fee_minor is outside the exact minor-unit range');
    if (trade.importId.isNotEmpty) {
      check(doc.imports.containsKey(trade.importId), 'trades', trade.id,
          'Unknown import_id ${trade.importId}');
    }
  }
}

/// Every trade settles through exactly one cash transaction that matches it.
///
/// Net worth adds cash balances to position values. Without this rule a trade
/// whose settlement row is missing leaves the spent cash in the balance, and the
/// total silently counts the same money twice.
void _validateTradeSettlements(TrackerDocument doc, _Check check) {
  final settlements = <String, List<Transaction>>{};
  for (final transaction in doc.transactions) {
    final tradeId = transaction.tradeKey;
    if (tradeId == null) continue;
    settlements.putIfAbsent(tradeId, () => []).add(transaction);

    // A row that is both would settle the trade and move the same cash to
    // another account, so the offsetting leg would fund the position twice.
    check(
      transaction.transferKey == null,
      'transactions',
      transaction.id,
      'A trade settlement cannot also be a transfer leg',
    );
  }

  final tradeIds = {for (final trade in doc.trades) trade.id};
  settlements.forEach((tradeId, rows) {
    if (tradeIds.contains(tradeId)) return;
    for (final row in rows) {
      check(false, 'transactions', row.id, 'Unknown trade_id $tradeId');
    }
  });

  for (final trade in doc.trades) {
    final rows = settlements[trade.id] ?? const <Transaction>[];
    if (rows.length != 1) {
      check(
        false,
        'trades',
        trade.id,
        'Trade needs exactly one settlement transaction, found ${rows.length}',
      );
      continue;
    }
    final row = rows.single;
    check(row.accountId == trade.accountId, 'trades', trade.id,
        'Settlement transaction is in account ${row.accountId}, not '
        '${trade.accountId}');
    check(row.currency == trade.currency, 'trades', trade.id,
        'Settlement currency ${row.currency} differs from ${trade.currency}');

    // Both rows are hidden or both are counted. A committed trade paired with a
    // pending settlement would add the position while its cash debit stays
    // invisible, which is exactly the overstatement this rule exists to stop.
    check(row.importId == trade.importId, 'trades', trade.id,
        'Settlement transaction has import_id "${row.importId}", not '
        '"${trade.importId}"');

    // Compared as BigInt: an amount that would overflow minor units is a
    // mismatch to report, not an exception thrown out of validation.
    final notional = trade.units.timesInt(trade.priceMinor).roundToBigInt();
    final fee = BigInt.from(trade.feeMinor);
    final expected = trade.side == TradeSide.buy
        ? -(notional + fee)
        : notional - fee;
    check(BigInt.from(row.amountMinor) == expected, 'trades', trade.id,
        'Settlement amount ${row.amountMinor} is not $expected');
  }
}

void _validatePrices(TrackerDocument doc, _Check check) {
  final keys = <String>{};
  for (final price in doc.prices) {
    final key = '${price.instrumentId}|${formatIsoDate(price.pricedOn)}'
        '|${price.currency}|${price.provider}';
    // A repeated key would make the latest observation depend on row order.
    check(keys.add(key), 'prices', key, 'Duplicate composite key');
    check(doc.instruments.containsKey(price.instrumentId), 'prices', key,
        'Unknown instrument_id ${price.instrumentId}');
    check(doc.currencies.containsKey(price.currency), 'prices', key,
        'Currency ${price.currency} has no currencies row');
    check(price.priceMinor >= 0, 'prices', key,
        'price_minor must not be negative');
    check(isExactMinor(price.priceMinor), 'prices', key,
        'price_minor is outside the exact minor-unit range');
  }
}

void _validateFxRates(TrackerDocument doc, _Check check) {
  final keys = <String>{};
  for (final rate in doc.fxRates) {
    final key = '${rate.baseCurrency}|${rate.quoteCurrency}'
        '|${formatIsoDate(rate.pricedOn)}|${rate.provider}';
    check(keys.add(key), 'fx_rates', key, 'Duplicate composite key');
    for (final code in [rate.baseCurrency, rate.quoteCurrency]) {
      check(doc.currencies.containsKey(code), 'fx_rates', key,
          'Currency $code has no currencies row');
    }
    // A zero or negative rate has no reciprocal, so no leg may hold one.
    check(rate.rate > Decimal.zero, 'fx_rates', key, 'rate must be positive');
  }
}
