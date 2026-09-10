/// Reads a canonical `.xlsx` tracker into the domain model.
///
/// The tabs, columns, and cell encoding are defined by
/// `docs/spreadsheet-format.md`. A value that cannot be normalized exactly is
/// reported, never guessed at and never silently rewritten: a workbook either
/// maps to the canonical model or it does not open. Nothing here writes.
library;

import 'package:archive/archive.dart';

import '../domain/decimal.dart';
import '../domain/models.dart';
import '../domain/schema.dart';
import 'xlsx_parts.dart';

export 'xlsx_parts.dart' show WorkbookFormatException;

/// Thrown when a workbook cannot be read exactly.
///
/// Carries every problem found rather than the first, so a user fixes the file
/// once. These are the same [ValidationError] values the dashboard renders.
class WorkbookError implements Exception {
  WorkbookError(this.errors);

  final List<ValidationError> errors;

  @override
  String toString() => 'WorkbookError:\n${errors.join('\n')}';
}

/// Reads workbook [bytes] into a tracker document.
///
/// The result is parsed, not validated: the caller runs [validateTracker] on
/// it, exactly as it does for any other document.
TrackerDocument readWorkbook(List<int> bytes) =>
    _Reader(WorkbookParts.decode(bytes)).read();

/// Reads the workbook at [path]. The file is opened read-only; v1 has no
/// writer, so nothing here can damage a tracker.
///
/// The compressed file is read from disk as the reader needs it rather than
/// held whole, so opening a large workbook costs its parts, not its parts plus
/// its bytes.
Future<TrackerDocument> openWorkbookFile(String path) async {
  final input = InputFileStream(path);
  try {
    return _Reader(WorkbookParts.decodeStream(input)).read();
  } finally {
    await input.close();
  }
}

typedef _Cell = Cell;

const _Cell _blank = blankCell;

class _Reader {
  _Reader(WorkbookParts parts) : _sheets = parts.sheets;

  /// Tab name to rows of cells, each already resolved against the workbook's
  /// shared strings, number formats, and date system.
  final Map<String, List<List<_Cell>>> _sheets;

  final List<ValidationError> _errors = [];

  void _fail(String entity, String id, String message) =>
      _errors.add(ValidationError(entity, id, message));

  TrackerDocument read() {
    final meta = _meta();
    final document = TrackerDocument(
      trackerId: meta['tracker_id'] ?? '',
      baseCurrency: meta['base_currency'] ?? '',
      currencies: _currencies(),
      accounts: _accounts(),
      portfolios: _portfolios(),
      categories: _categories(),
      instruments: _instruments(),
      transactions: _transactions(),
      trades: _trades(),
      prices: _prices(),
      fxRates: _fxRates(),
      imports: _imports(),
    );
    if (_errors.isNotEmpty) throw WorkbookError(_errors);
    return document;
  }

  /// The `_meta` key/value tab.
  ///
  /// A `format_version` other than 1 describes a canonical model this release
  /// does not implement, so the workbook is refused rather than half-read.
  Map<String, String> _meta() {
    final values = <String, String>{};
    final sheet = _sheets['_meta'];
    if (sheet == null) {
      _fail('_meta', 'tab', 'Workbook has no _meta tab');
      return values;
    }
    for (final row in sheet) {
      final key = row.elementAtOrNull(0) ?? _blank;
      if (key.text.isEmpty || key.text == 'key') continue;
      final value = row.elementAtOrNull(1) ?? _blank;
      if (key.kind == CellKind.opaque || value.kind == CellKind.opaque) {
        _fail('_meta', key.text, 'Value has no exact text; formulas are not '
            'part of the format');
        continue;
      }
      // A second row for one key would quietly replace the first, changing the
      // base currency or tracker identity of everything already read.
      if (values.containsKey(key.text)) {
        _fail('_meta', key.text, 'Key appears more than once');
        continue;
      }
      values[key.text] = value.text;
    }
    final version = values['format_version'] ?? '';
    if (version != '1') {
      _fail('_meta', 'format_version', 'Unsupported format_version "$version"');
    }
    for (final key in ['tracker_id', 'base_currency']) {
      if ((values[key] ?? '').isEmpty) _fail('_meta', key, 'Missing $key');
    }
    return values;
  }

  Map<String, int> _currencies() {
    final currencies = <String, int>{};
    for (final row in _rows('currencies', const ['code', 'minor_unit'])) {
      final code = row['code']!.text;
      _unique(currencies.containsKey(code), 'currencies', code);
      currencies[code] = _int('currencies', code, 'minor_unit', row);
    }
    return currencies;
  }

  Map<String, Account> _accounts() {
    final accounts = <String, Account>{};
    for (final row in _rows(
      'accounts',
      const ['id', 'name', 'type', 'currency', 'archived'],
      optional: const ['portfolio_id'],
    )) {
      final id = row['id']!.text;
      _unique(accounts.containsKey(id), 'accounts', id);
      accounts[id] = Account(
        id: id,
        name: _text('accounts', id, 'name', row),
        type: _text('accounts', id, 'type', row),
        currency: _text('accounts', id, 'currency', row),
        archived: _bool('accounts', id, 'archived', row),
        portfolioId: _optional(_text('accounts', id, 'portfolio_id', row)),
      );
    }
    return accounts;
  }

  /// Optional: a tracker that groups nothing has no `portfolios` tab, and its
  /// investment accounts are all reported as unassigned.
  Map<String, Portfolio> _portfolios() {
    final portfolios = <String, Portfolio>{};
    for (final row in _rows('portfolios', const ['id', 'name'])) {
      final id = row['id']!.text;
      _unique(portfolios.containsKey(id), 'portfolios', id);
      portfolios[id] = Portfolio(
        id: id,
        name: _text('portfolios', id, 'name', row),
      );
    }
    return portfolios;
  }

  Map<String, Category> _categories() {
    final categories = <String, Category>{};
    for (final row in _rows('categories', const [
      'id',
      'name',
      'parent_id',
      'type',
    ])) {
      final id = row['id']!.text;
      _unique(categories.containsKey(id), 'categories', id);
      categories[id] = Category(
        id: id,
        name: _text('categories', id, 'name', row),
        type: _enum('categories', id, 'type', row, CategoryType.values),
        parentId: _optional(_text('categories', id, 'parent_id', row)),
      );
    }
    return categories;
  }

  Map<String, Instrument> _instruments() {
    final instruments = <String, Instrument>{};
    for (final row in _rows('instruments', const [
      'id',
      'symbol',
      'name',
      'type',
      'currency',
    ])) {
      final id = row['id']!.text;
      _unique(instruments.containsKey(id), 'instruments', id);
      instruments[id] = Instrument(
        id: id,
        symbol: _text('instruments', id, 'symbol', row),
        name: _text('instruments', id, 'name', row),
        type: _text('instruments', id, 'type', row),
        currency: _text('instruments', id, 'currency', row),
      );
    }
    return instruments;
  }

  List<Transaction> _transactions() {
    final transactions = <Transaction>[];
    for (final row in _rows('transactions', const [
      'id',
      'account_id',
      'booked_on',
      'amount_minor',
      'currency',
      'payee',
      'description',
      'category_id',
      'transfer_id',
      'trade_id',
      'source',
      'source_id',
      'row_fingerprint',
      'import_id',
      'created_at',
    ])) {
      final id = row['id']!.text;
      transactions.add(
        Transaction(
          id: id,
          accountId: _text('transactions', id, 'account_id', row),
          bookedOn: _date('transactions', id, 'booked_on', row),
          amountMinor: _minor('transactions', id, 'amount_minor', row),
          currency: _text('transactions', id, 'currency', row),
          payee: _text('transactions', id, 'payee', row),
          description: _text('transactions', id, 'description', row),
          categoryId: _optional(_text('transactions', id, 'category_id', row)),
          transferId: _optional(_text('transactions', id, 'transfer_id', row)),
          tradeId: _optional(_text('transactions', id, 'trade_id', row)),
          source: _text('transactions', id, 'source', row),
          sourceId: _text('transactions', id, 'source_id', row),
          rowFingerprint: _text('transactions', id, 'row_fingerprint', row),
          importId: _text('transactions', id, 'import_id', row),
          createdAt: _timestamp('transactions', id, 'created_at', row),
        ),
      );
    }
    return transactions;
  }

  List<Trade> _trades() {
    final trades = <Trade>[];
    for (final row in _rows('trades', const [
      'id',
      'account_id',
      'instrument_id',
      'traded_on',
      'side',
      'units',
      'price_minor',
      'fee_minor',
      'currency',
      'source',
      'source_id',
      'row_fingerprint',
      'import_id',
    ])) {
      final id = row['id']!.text;
      trades.add(
        Trade(
          id: id,
          accountId: _text('trades', id, 'account_id', row),
          instrumentId: _text('trades', id, 'instrument_id', row),
          tradedOn: _date('trades', id, 'traded_on', row),
          side: _enum('trades', id, 'side', row, TradeSide.values),
          units: _decimal('trades', id, 'units', row),
          priceMinor: _minor('trades', id, 'price_minor', row),
          feeMinor: _minor('trades', id, 'fee_minor', row),
          currency: _text('trades', id, 'currency', row),
          source: _text('trades', id, 'source', row),
          sourceId: _text('trades', id, 'source_id', row),
          rowFingerprint: _text('trades', id, 'row_fingerprint', row),
          importId: _text('trades', id, 'import_id', row),
        ),
      );
    }
    return trades;
  }

  List<Price> _prices() {
    final prices = <Price>[];
    for (final row in _rows('prices', const [
      'instrument_id',
      'priced_on',
      'price_minor',
      'currency',
      'provider',
    ])) {
      final id = row['instrument_id']!.text;
      prices.add(
        Price(
          instrumentId: id,
          pricedOn: _date('prices', id, 'priced_on', row),
          priceMinor: _minor('prices', id, 'price_minor', row),
          currency: _text('prices', id, 'currency', row),
          provider: _text('prices', id, 'provider', row),
        ),
      );
    }
    return prices;
  }

  List<FxRate> _fxRates() {
    final rates = <FxRate>[];
    for (final row in _rows('fx_rates', const [
      'base_currency',
      'quote_currency',
      'priced_on',
      'rate',
      'provider',
    ])) {
      final id = row['base_currency']!.text;
      rates.add(
        FxRate(
          baseCurrency: id,
          quoteCurrency: _text('fx_rates', id, 'quote_currency', row),
          pricedOn: _date('fx_rates', id, 'priced_on', row),
          rate: _decimal('fx_rates', id, 'rate', row),
          provider: _text('fx_rates', id, 'provider', row),
        ),
      );
    }
    return rates;
  }

  /// Only `id` and `status` reach the model: an import's lease and counts drive
  /// importing, which is not implemented, and the engine needs the status alone
  /// to hide rows of an import that has not committed.
  Map<String, ImportStatus> _imports() {
    final imports = <String, ImportStatus>{};
    for (final row in _rows('imports', const ['id', 'status'])) {
      final id = row['id']!.text;
      _unique(imports.containsKey(id), 'imports', id);
      imports[id] = _enum('imports', id, 'status', row, ImportStatus.values);
    }
    return imports;
  }

  /// Rows of one tab, keyed by column name. An absent tab is empty, not an
  /// error: a tracker without trades has nothing to put in that tab.
  ///
  /// Columns beyond [columns] are ignored, so a user's extra note column does
  /// not block opening. A row whose `id` column is blank is skipped: writers
  /// leave trailing empty rows behind.
  ///
  /// [optional] columns are read when the header has them and read as blank
  /// when it does not, which is what keeps a workbook written before a column
  /// existed readable by this release.
  List<Map<String, _Cell>> _rows(
    String tab,
    List<String> columns, {
    List<String> optional = const [],
  }) {
    final sheet = _sheets[tab];
    if (sheet == null || sheet.isEmpty) return const [];

    final header = <String, int>{};
    final headerRow = sheet.first;
    for (var index = 0; index < headerRow.length; index++) {
      final cell = headerRow[index];
      final name = cell.text;
      if (name.isEmpty) continue;
      // A formula that happens to render a canonical column name would let its
      // whole column through unchecked.
      if (cell.kind == CellKind.opaque) {
        _fail(tab, 'header', 'Column ${index + 1} holds a formula, not a name');
        return const [];
      }
      // Two columns of one canonical name make every row ambiguous: the second
      // would quietly win and could report a different amount entirely.
      if (header.containsKey(name)) {
        _fail(tab, 'header', 'Column $name appears more than once');
        return const [];
      }
      header[name] = index;
    }
    final missing = columns.where((c) => !header.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      _fail(tab, 'header', 'Missing column${missing.length == 1 ? '' : 's'} '
          '${missing.join(', ')}');
      return const [];
    }

    final rows = <Map<String, _Cell>>[];
    for (final row in sheet.skip(1)) {
      final cells = {
        for (final column in [...columns, ...optional])
          column: header[column] == null
              ? _blank
              : row.elementAtOrNull(header[column]!) ?? _blank,
      };
      if (cells.values.every((cell) => cell.text.isEmpty)) continue;
      // The first column identifies the row and is read as text everywhere
      // below, so it is checked here rather than through `_text`.
      final key = cells[columns.first]!;
      if (key.text.isEmpty || key.kind == CellKind.opaque) {
        _fail(tab, 'row ${rows.length + 2}', key.text.isEmpty
            ? '${columns.first} is blank'
            : '${columns.first} holds a formula, not an identifier');
        continue;
      }
      rows.add(cells);
    }
    return rows;
  }

  void _unique(bool duplicate, String entity, String id) {
    if (duplicate) _fail(entity, id, 'Duplicate id; a later row would hide it');
  }

  String _text(String entity, String id, String column, Map<String, _Cell> row) {
    final cell = row[column]!;
    if (cell.kind == CellKind.opaque) {
      _fail(entity, id, '$column holds a formula or a value with no exact text');
      return '';
    }
    return cell.text;
  }

  static String? _optional(String value) => value.isEmpty ? null : value;

  int _int(String entity, String id, String column, Map<String, _Cell> row) {
    final text = _text(entity, id, column, row);
    final value = int.tryParse(text);
    if (value == null) _fail(entity, id, '$column "$text" is not an integer');
    return value ?? 0;
  }

  /// A minor amount may come from a text or numeric cell, but only when the
  /// number is an exact integer this platform holds without rounding.
  int _minor(String entity, String id, String column, Map<String, _Cell> row) {
    final value = _int(entity, id, column, row);
    if (!isExactMinor(value)) {
      _fail(entity, id, '$column is outside the exact minor-unit range');
      return 0;
    }
    return value;
  }

  /// Decimals are text only: a numeric `units` or `rate` cell has already lost
  /// its original precision to IEEE-754 by the time it reaches a reader.
  Decimal _decimal(
    String entity,
    String id,
    String column,
    Map<String, _Cell> row,
  ) {
    final cell = row[column]!;
    if (cell.kind != CellKind.text) {
      _fail(entity, id, '$column must be a text cell, not a number');
      return Decimal.zero;
    }
    final value = Decimal.tryParse(cell.text);
    if (value == null) {
      _fail(entity, id, '$column "${cell.text}" is not a decimal string');
    }
    return value ?? Decimal.zero;
  }

  /// ISO text, or a cell the workbook itself formatted as a date. A bare number
  /// is refused: a serial without a date format carries no date system.
  DateTime _date(String entity, String id, String column, Map<String, _Cell> row) {
    final cell = row[column]!;
    if (cell.kind == CellKind.text || cell.kind == CellKind.date) {
      try {
        return parseIsoDate(cell.text);
      } on FormatException {
        _fail(entity, id, '$column "${cell.text}" is not a YYYY-MM-DD date');
        return DateTime.utc(0);
      }
    }
    _fail(entity, id, '$column must be an ISO date or a date-formatted cell');
    return DateTime.utc(0);
  }

  static final RegExp _rfc3339Utc = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$',
  );

  /// RFC 3339 UTC text. Blank means the row carries no timestamp.
  ///
  /// The components are checked against the calendar rather than handed to
  /// `DateTime.parse`, which rolls an impossible date forward: `2026-02-31`
  /// would otherwise be stored, and later reported, as 3 March.
  DateTime? _timestamp(
    String entity,
    String id,
    String column,
    Map<String, _Cell> row,
  ) {
    final cell = row[column]!;
    if (cell.text.isEmpty) return null;
    final match = cell.kind == CellKind.text
        ? _rfc3339Utc.firstMatch(cell.text)
        : null;
    if (match != null) {
      final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
      final value = DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
        0,
        int.parse((match.group(7) ?? '').padRight(6, '0').substring(0, 6)),
      );
      final unchanged = [
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
      ];
      if (unchanged.toString() == parts.toString()) return value;
    }
    _fail(entity, id, '$column "${cell.text}" is not an RFC 3339 UTC time');
    return null;
  }

  bool _bool(String entity, String id, String column, Map<String, _Cell> row) {
    final text = _text(entity, id, column, row).toLowerCase();
    if (text.isEmpty || text == 'false') return false;
    if (text == 'true') return true;
    _fail(entity, id, '$column "$text" is not true or false');
    return false;
  }

  T _enum<T extends Enum>(
    String entity,
    String id,
    String column,
    Map<String, _Cell> row,
    List<T> values,
  ) {
    final text = _text(entity, id, column, row);
    final value = values.where((v) => v.name == text).firstOrNull;
    if (value == null) {
      _fail(entity, id, '$column "$text" is not one of '
          '${values.map((v) => v.name).join(', ')}');
    }
    return value ?? values.first;
  }
}
