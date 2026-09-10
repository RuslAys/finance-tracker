/// The computed, scoped finance snapshot an LLM, MCP tool, or skill may see.
///
/// `docs/privacy-and-llm.md` allows exactly this much outside the app: totals,
/// the period they cover, categories, the selected holdings, and freshness and
/// completeness markers. Everything else stays here — no transaction rows, no
/// payees or descriptions, no bank identity (`source`, `source_id`,
/// `row_fingerprint`, `import_id`), no custom columns, no file path, and no
/// credentials. A snapshot is a report, not an export of the tracker.
///
/// Row identity stays here too. An account is named by a pseudonym built from
/// its type and currency, valid only inside one snapshot, because a user's own
/// account name can name their bank, their employer, or a family member. The
/// UUIDs of accounts, categories, instruments, transactions, and trades are the
/// tracker's row identity and never leave: a consumer that needs to point at a
/// row is asking for the document, which no snapshot grants.
///
/// Every number is produced by [FinanceEngine], so a snapshot can only ever
/// restate what the deterministic client already computed. Nothing here decides
/// money, and nothing downstream may recompute it.
library;

import 'decimal.dart';
import 'finance.dart';
import 'fx.dart';
import 'models.dart';
import 'schema.dart';

/// One account's balance, in that account's own currency.
///
/// [ref] is the pseudonym this snapshot uses for the account, such as
/// `cash EUR 1`. It says what kind of account holds the balance without saying
/// whose it is or which institution keeps it, and it means nothing outside the
/// snapshot that issued it.
class AccountSummary {
  const AccountSummary({
    required this.ref,
    required this.type,
    required this.currency,
    required this.balanceMinor,
  });

  final String ref;
  final String type;
  final String currency;

  /// Null when the balance could not be computed exactly. An account whose
  /// total this platform cannot hold holds an unknown amount, never zero.
  final Minor? balanceMinor;

  Map<String, Object?> toJson() => {
    'account': ref,
    'type': type,
    'currency': currency,
    'balance_minor': balanceMinor,
  };
}

/// One category's signed total over the period, in the reporting currency.
class CategoryFlow {
  const CategoryFlow({required this.name, required this.amountMinor});

  /// The category's name, or `Uncategorized` for the rows that have none. The
  /// name is what a report is about; its UUID is row identity and stays behind.
  final String name;
  final Minor amountMinor;

  Map<String, Object?> toJson() => {
    'name': name,
    'amount_minor': amountMinor,
  };
}

/// One FIFO book on the valuation date.
///
/// Units are a decimal string and amounts are minor units, as everywhere else:
/// a snapshot carries the same exact values the engine computed, never a float
/// a reader would have to trust.
class PositionSummary {
  const PositionSummary({
    required this.accountRef,
    required this.symbol,
    required this.currency,
    required this.units,
    required this.costMinor,
    required this.realizedGainMinor,
    required this.valueMinor,
  });

  /// The same pseudonym [AccountSummary.ref] uses, so a consumer can tell which
  /// reported balance this position sits beside without learning the account.
  final String accountRef;

  /// The instrument's ticker, which is public. Its UUID is row identity and
  /// stays behind; an instrument with no symbol is reported as `instrument N`.
  final String symbol;

  /// Settlement currency of the book, which every amount below is stated in.
  final String currency;
  final String units;
  final Minor costMinor;
  final Minor realizedGainMinor;

  /// Market value, or null when the position has no price on the valuation
  /// date. An unpriced position is unavailable, never zero.
  final Minor? valueMinor;

  Map<String, Object?> toJson() => {
    'account': accountRef,
    'symbol': symbol,
    'currency': currency,
    'units': units,
    'cost_minor': costMinor,
    'realized_gain_minor': realizedGainMinor,
    'value_minor': valueMinor,
  };
}

/// A computed report of one tracker, scoped to some of its accounts.
///
/// [incomplete] carries the reasons a total is missing. A consumer states them:
/// a snapshot whose net worth is null describes a tracker whose net worth could
/// not be computed, which is not a tracker worth nothing.
class FinanceSnapshot {
  const FinanceSnapshot({
    required this.trackerId,
    required this.baseCurrency,
    required this.asOf,
    required this.computedAt,
    required this.periodStart,
    required this.periodEnd,
    required this.scopeLabel,
    required this.accounts,
    required this.netWorthMinor,
    required this.income,
    required this.expense,
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.netMinor,
    required this.positions,
    required this.minorUnits,
    required this.incomplete,
  });

  /// Identity of the tracker this describes, and the valuation date every
  /// balance, price, and rate in it resolves on or before. The companion
  /// returns both with every result, so an answer cannot be mistaken for a
  /// report of another tracker or another day.
  final String trackerId;
  final DateTime asOf;

  /// When these numbers were calculated. Not a claim about how current the
  /// underlying records are: nothing in this app fetches from a bank.
  final DateTime computedAt;

  /// Currency of the period totals, net worth, and every converted amount.
  final String baseCurrency;

  /// The reported period, both days inclusive.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// What the scope covers, in the words a consumer may repeat: a portfolio
  /// name, or the whole tracker.
  final String scopeLabel;

  final List<AccountSummary> accounts;

  /// Null when the period could not be computed. An empty list is a period in
  /// which nothing was earned or spent, which is a different report.
  final List<CategoryFlow>? income;
  final List<CategoryFlow>? expense;

  /// Null when the FIFO books could not be replayed. An empty list is a scope
  /// that holds no positions, which is a different report.
  final List<PositionSummary>? positions;

  /// Null when a rate, a price, or half a recorded movement makes the total
  /// undefined; [incomplete] then says which.
  final Minor? netWorthMinor;
  final Minor? totalIncomeMinor;
  final Minor? totalExpenseMinor;

  /// Income less expense over the period. Null when either side is missing, or
  /// when the difference itself leaves the exact minor-unit range: a total this
  /// platform cannot hold exactly is unavailable, not approximate.
  final Minor? netMinor;

  /// Decimal places of every currency named above, so a consumer can render an
  /// amount without guessing that it has two.
  final Map<String, int> minorUnits;

  /// Why a total above is missing. Empty means every total is computed.
  final List<String> incomplete;

  bool get isComplete => incomplete.isEmpty;

  Map<String, Object?> toJson() => {
    'tracker_id': trackerId,
    'as_of': formatIsoDate(asOf),
    'computed_at': computedAt.toUtc().toIso8601String(),
    'base_currency': baseCurrency,
    'scope': scopeLabel,
    'period': {
      'from': formatIsoDate(periodStart),
      'to': formatIsoDate(periodEnd),
    },
    'minor_units': minorUnits,
    'net_worth_minor': netWorthMinor,
    'accounts': [for (final account in accounts) account.toJson()],
    // Null, not an empty list: a period whose totals could not be computed did
    // not have nothing in it, and books that could not be replayed are not a
    // scope that holds nothing.
    'income': _flowsJson(income),
    'expense': _flowsJson(expense),
    'total_income_minor': totalIncomeMinor,
    'total_expense_minor': totalExpenseMinor,
    'net_minor': netMinor,
    'positions': positions == null
        ? null
        : [for (final position in positions!) position.toJson()],
    'complete': isComplete,
    'incomplete': incomplete,
  };
}

/// Market value of [holding] in the position's own settlement currency, which
/// is the currency the snapshot states its cost in.
///
/// A quote in the instrument's reference currency is converted at the valuation
/// date; without a price, or without that rate, the position is unpriced rather
/// than valued in a currency the snapshot never named.
Minor? _valueOf(
  TrackerDocument doc,
  Holding holding, {
  required FxConverter fx,
  required String priceProvider,
  required DateTime asOf,
}) {
  final quote = FinanceEngine.marketValue(
    doc,
    holding,
    provider: priceProvider,
    asOf: asOf,
  );
  if (quote == null) return null;
  return fx.convertMinor(
    quote.amount,
    from: quote.currency,
    to: holding.currency,
    asOf: asOf,
  );
}

List<Map<String, Object?>>? _flowsJson(List<CategoryFlow>? flows) =>
    flows == null ? null : [for (final flow in flows) flow.toJson()];

/// [compute], or null when it leaves the exact minor-unit range.
///
/// Two totals this platform holds exactly can still have a sum or difference it
/// does not, and a snapshot that threw while being serialized would fail after
/// its caller already believed it had a report.
Minor? _exact(Minor? Function() compute) {
  try {
    return compute();
  } on RangeError {
    return null;
  }
}

/// Computes the snapshot of [doc] that may leave the app.
///
/// [accountIds] scopes the report; null covers every account. Scoping is a
/// reporting boundary, not an access control: the caller decides what was
/// approved, and this only guarantees that nothing outside the scope is
/// counted, named, or valued.
///
/// Every total is withheld rather than estimated when the tracker cannot
/// support it: a validation error, an impossible sell, a missing price, or a
/// missing rate leaves the total null and its reason in `incomplete`.
FinanceSnapshot buildSnapshot(
  TrackerDocument doc, {
  required DateTime asOf,
  required DateTime periodStart,
  required DateTime periodEnd,
  Iterable<String>? accountIds,
  String scopeLabel = 'All accounts',
  String priceProvider = 'demo',
  String rateProvider = 'demo',
  DateTime? computedAt,
}) {
  final ids = accountIds?.toSet();
  final scoped = [
    for (final account in doc.accounts.values)
      if (ids == null || ids.contains(account.id)) account,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final incomplete = <String>[];

  final fx = FxConverter(doc, provider: rateProvider);

  /// [compute], or null with its reason recorded.
  ///
  /// Each result is attempted on its own so that one impossible total does not
  /// take the rest of the report down with it — and, more importantly, so that
  /// a failure leaves that result missing. A caught error that fell back to an
  /// empty collection would be serialized as a balance of zero and a period
  /// that earned and spent nothing, which reads as a real report of a real
  /// tracker. A [FinanceError] names the trade it is about and any other error
  /// may carry a value out of the document, so neither text is repeated.
  T? attempt<T>(T Function() compute, String unavailable) {
    try {
      return compute();
    } catch (error) {
      incomplete.add(
        error is FinanceError
            ? '$unavailable: the trade history cannot be replayed'
            : '$unavailable: a total is outside the exact minor-unit range',
      );
      return null;
    }
  }

  final balances = attempt(
    () => FinanceEngine.accountBalances(doc, asOf: asOf, accountIds: ids),
    'Account balances are unavailable',
  );
  final cashFlow = attempt(
    () => FinanceEngine.cashFlow(
      doc,
      currency: doc.baseCurrency,
      from: periodStart,
      to: periodEnd,
      fx: fx,
      accountIds: ids,
    ),
    'The period totals are unavailable',
  );
  // Null, never an empty list: an impossible sell leaves the books unreadable,
  // and reporting no positions would state the accounts hold nothing.
  final positions = attempt(
    () => FinanceEngine.holdings(doc, asOf: asOf, accountIds: ids),
    'Holdings are unavailable',
  );
  // Net worth covers the whole tracker by definition, so a scoped snapshot does
  // not state one: the accounts it left out hold money too.
  final netWorth = ids != null
      ? null
      : attempt(
          () => FinanceEngine.netWorth(
            doc,
            priceProvider: priceProvider,
            rateProvider: rateProvider,
            asOf: asOf,
          ),
          'Net worth is unavailable',
        );
  if (ids != null) {
    incomplete.add('Net worth covers the whole tracker, not $scopeLabel');
  } else if (netWorth == null) {
    incomplete.add('Net worth is unavailable on ${formatIsoDate(asOf)}');
  }
  for (final currency in cashFlow?.unconvertedCurrencies ?? const <String>{}) {
    incomplete.add('No rate from $currency to ${doc.baseCurrency} in the '
        'reported period');
  }

  final held = positions ?? const <Holding>[];
  final currencies = {
    doc.baseCurrency,
    for (final account in scoped) account.currency,
    for (final position in held) position.currency,
  };

  // A category with no name of its own is reported as uncategorized rather than
  // by its UUID, which is row identity.
  String categoryName(String id) =>
      doc.categories[id]?.name ?? 'Uncategorized';
  // Null rather than empty when the period could not be computed: a report of
  // no categories is a period in which nothing happened.
  List<CategoryFlow>? flows(Map<String, Minor>? byCategory) {
    if (byCategory == null) return null;
    return [
      for (final entry in byCategory.entries)
        CategoryFlow(name: categoryName(entry.key), amountMinor: entry.value),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  // Pseudonyms, numbered in the order the accounts are reported, so the same
  // document scoped differently issues different refs: a ref identifies a line
  // of this snapshot, never an account of the tracker.
  final refs = <String, String>{};
  final perKind = <String, int>{};
  for (final account in scoped) {
    final kind = '${account.type} ${account.currency}';
    final index = (perKind[kind] ?? 0) + 1;
    perKind[kind] = index;
    refs[account.id] = '$kind $index';
  }
  String refOf(String accountId) => refs[accountId] ?? 'account';

  final symbols = <String, String>{};
  String symbolOf(String instrumentId) => symbols.putIfAbsent(instrumentId, () {
    final symbol = doc.instruments[instrumentId]?.symbol ?? '';
    return symbol.isEmpty ? 'instrument ${symbols.length + 1}' : symbol;
  });

  // Valuing a position can fail as well as be impossible: units times a price
  // can leave the exact minor-unit range even though both are stored exactly.
  // That is one position's problem, so it is caught per position rather than
  // taking the whole snapshot down with it.
  final unpriced = <String>{};
  final inexact = <String>{};
  final reported = [
    for (final holding in held)
      (
        holding: holding,
        value: () {
          try {
            final value = _valueOf(
              doc,
              holding,
              fx: fx,
              priceProvider: priceProvider,
              asOf: asOf,
            );
            if (value == null) unpriced.add(symbolOf(holding.instrumentId));
            return value;
          } catch (_) {
            inexact.add(symbolOf(holding.instrumentId));
            return null;
          }
        }(),
      ),
  ];
  // An unvalued position has to say so itself: in a scoped snapshot no net
  // worth is stated, so nothing else would ever report the missing price.
  String list(Set<String> symbols) => (symbols.toList()..sort()).join(', ');
  if (unpriced.isNotEmpty) {
    incomplete.add('No price or rate for ${list(unpriced)} '
        'on ${formatIsoDate(asOf)}');
  }
  if (inexact.isNotEmpty) {
    incomplete.add('The value of ${list(inexact)} is outside the exact '
        'minor-unit range');
  }

  // The report is only as trustworthy as the records under it, so a broken
  // document is declared rather than quietly reported on. Only how many rows of
  // which tab fail is declared — a validation message names the row it is about
  // — and only for the records this snapshot actually read: the engine's own
  // report scoping decides that, so a caller approved for some accounts learns
  // nothing about the rest, not even how many of their rows are broken.
  final failures = <String, int>{};
  for (final error in ids == null
      ? validateTracker(doc)
      : FinanceEngine.scopedErrors(
          doc,
          ids,
          quoteCurrencies: {
            for (final holding in held)
              if (holding.units != Decimal.zero)
                holding.instrumentId: {
                  holding.currency,
                  ?doc.instruments[holding.instrumentId]?.currency,
                },
          },
          currencies: currencies,
          // Every currency this snapshot converts between: the period converts
          // a row's own currency to the base one, and a quote converts to the
          // currency of the book holding it.
          fxCurrencies: currencies,
          priceProvider: priceProvider,
          rateProvider: rateProvider,
          asOf: asOf,
        )) {
    failures.update(error.entity, (count) => count + 1, ifAbsent: () => 1);
  }
  for (final entry in failures.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    incomplete.add('${entry.value} ${entry.key} '
        '${entry.value == 1 ? 'row fails' : 'rows fail'} validation');
  }

  // Each side is within the exact range, and their difference need not be. A
  // total this platform cannot hold exactly is unavailable, never rounded into
  // one that reads as real.
  final totalIncome = _exact(() => cashFlow?.totalIncome);
  final totalExpense = _exact(() => cashFlow?.totalExpense);
  final net = totalIncome == null || totalExpense == null
      ? null
      : _exact(() => subtractMinor(totalIncome, totalExpense));
  if ((cashFlow?.isComplete ?? false) &&
      (totalIncome == null || totalExpense == null)) {
    incomplete.add('A period total is outside the exact minor-unit range');
  } else if (net == null && totalIncome != null && totalExpense != null) {
    incomplete.add('Income less expense is outside the exact minor-unit range');
  }

  return FinanceSnapshot(
    trackerId: doc.trackerId,
    baseCurrency: doc.baseCurrency,
    asOf: asOf,
    computedAt: computedAt ?? DateTime.now().toUtc(),
    periodStart: periodStart,
    periodEnd: periodEnd,
    scopeLabel: scopeLabel,
    accounts: [
      for (final account in scoped)
        AccountSummary(
          ref: refOf(account.id),
          type: account.type,
          currency: account.currency,
          // Null when the balances could not be computed: an account whose
          // total this platform cannot hold exactly holds an unknown amount,
          // never zero.
          balanceMinor: balances == null ? null : balances[account.id] ?? 0,
        ),
    ],
    netWorthMinor: netWorth,
    income: flows(cashFlow?.incomeByCategory),
    expense: flows(cashFlow?.expenseByCategory),
    totalIncomeMinor: totalIncome,
    totalExpenseMinor: totalExpense,
    netMinor: net,
    positions: positions == null
        ? null
        : [
            for (final entry in reported)
              PositionSummary(
                accountRef: refOf(entry.holding.accountId),
                symbol: symbolOf(entry.holding.instrumentId),
                currency: entry.holding.currency,
                units: '${entry.holding.units}',
                costMinor: entry.holding.costMinor,
                realizedGainMinor: entry.holding.realizedGainMinor,
                valueMinor: entry.value,
              ),
          ],
    minorUnits: {
      for (final currency in currencies.toList()..sort())
        currency: ?doc.currencies[currency],
    },
    incomplete: incomplete,
  );
}
