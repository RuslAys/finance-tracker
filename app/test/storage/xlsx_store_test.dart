import 'dart:typed_data';

import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/finance.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/schema.dart';
import 'package:finance_tracker/storage/xlsx_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'xlsx_builder.dart';

/// The same container with ZIP64 records inserted before its End of Central
/// Directory record.
///
/// With [wholeFileIsDirectory] the ZIP64 records claim the container itself as
/// the central directory — the shape of an archive whose directory holds one
/// record per 46 bytes of file — while the 32-bit fields keep the writer's
/// small, honest values. That is exactly what a reader consulting ZIP64 only
/// for the `0xffffffff` sentinel never looks at, and what the decoder takes
/// regardless. Otherwise the records restate the real directory.
///
/// The records go between the central directory and the trailing record, so
/// every stored offset still points where it did.
List<int> _withZip64Directory(
  List<int> container, {
  bool wholeFileIsDirectory = false,
}) {
  final zip = Uint8List.fromList(container);
  // The builder writes no comment, so the record is the last 22 bytes.
  final eocd = zip.length - 22;
  final trailer = ByteData.sublistView(zip, eocd);
  final zip64 = ByteData(56)
    ..setUint32(0, 0x06064b50, Endian.little)
    ..setUint64(4, 44, Endian.little)
    ..setUint64(24, 1, Endian.little)
    ..setUint64(32, 1, Endian.little)
    ..setUint64(
      40,
      wholeFileIsDirectory ? zip.length : trailer.getUint32(12, Endian.little),
      Endian.little,
    )
    ..setUint64(
      48,
      wholeFileIsDirectory ? 0 : trailer.getUint32(16, Endian.little),
      Endian.little,
    );
  final locator = ByteData(20)
    ..setUint32(0, 0x07064b50, Endian.little)
    ..setUint64(8, eocd, Endian.little)
    ..setUint32(16, 1, Endian.little);
  return [
    ...zip.sublist(0, eocd),
    ...zip64.buffer.asUint8List(),
    ...locator.buffer.asUint8List(),
    ...zip.sublist(eocd),
  ];
}

/// A small but complete canonical workbook: one funded position, one price, one
/// rate. Cells are text except where a test needs another cell type.
Map<String, List<List<TestCell>>> _tabs() => {
  '_meta': [
    texts(['key', 'value']),
    texts(['format_version', '1']),
    texts(['layout_version', '1']),
    texts(['mapping_version', '1']),
    texts(['tracker_id', 'trk-1']),
    texts(['base_currency', 'EUR']),
  ],
  'currencies': [
    texts(['code', 'minor_unit']),
    texts(['EUR', '2']),
    texts(['USD', '2']),
  ],
  'accounts': [
    texts(['id', 'name', 'type', 'currency', 'archived']),
    // Shared strings are the common encoding for repeated text, and `archived`
    // as a real boolean cell is what a spreadsheet writes for a checkbox.
    [shared('acc-1'), shared('Checking'), shared('cash'), shared('EUR'),
      boolean(false)],
    [shared('acc-2'), shared('Broker'), shared('brokerage'), shared('EUR'),
      text('')],
  ],
  'categories': [
    texts(['id', 'name', 'parent_id', 'type']),
    texts(['cat-1', 'Salary', '', 'income']),
  ],
  'instruments': [
    texts(['id', 'symbol', 'name', 'type', 'currency']),
    texts(['ins-1', 'VWCE', 'World ETF', 'etf', 'EUR']),
  ],
  'transactions': [
    texts([
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
    ]),
    [
      text('tx-1'),
      text('acc-1'),
      // A date-formatted serial, as a spreadsheet stores a typed-in date.
      dateSerial('46082'),
      // A numeric minor amount, exact because it is a whole number.
      number('320000'),
      ...texts(['EUR', 'Employer', '', 'cat-1', '', '', 'manual', '', '', '']),
      text('2026-03-01T09:30:00Z'),
    ],
    texts([
      'tx-2',
      'acc-2',
      '2026-03-05',
      '-20000',
      'EUR',
      'VWCE buy',
      '',
      '',
      '',
      'trd-1',
      'manual',
      '',
      '',
      '',
      '',
    ]),
  ],
  'trades': [
    texts([
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
    ]),
    texts([
      'trd-1',
      'acc-2',
      'ins-1',
      '2026-03-05',
      'buy',
      '2',
      '10000',
      '0',
      'EUR',
      'manual',
      '',
      '',
      '',
    ]),
  ],
  'prices': [
    texts(['instrument_id', 'priced_on', 'price_minor', 'currency', 'provider']),
    texts(['ins-1', '2026-03-06', '11000', 'EUR', 'demo']),
  ],
  'fx_rates': [
    texts(['base_currency', 'quote_currency', 'priced_on', 'rate', 'provider']),
    texts(['EUR', 'USD', '2026-03-01', '1.08', 'demo']),
  ],
};

TrackerDocument _read(
  Map<String, List<List<TestCell>>> tabs, {
  bool date1904 = false,
}) => readWorkbook(buildXlsx(tabs, date1904: date1904));

List<ValidationError> _errorsOf(
  Map<String, List<List<TestCell>>> tabs, {
  bool date1904 = false,
  String customNumberFormat = '[Red]0',
}) {
  try {
    readWorkbook(
      buildXlsx(
        tabs,
        date1904: date1904,
        customNumberFormat: customNumberFormat,
      ),
    );
  } on WorkbookError catch (error) {
    return error.errors;
  }
  return const [];
}

Matcher _reports(String fragment) => contains(
  predicate<ValidationError>(
    (error) => error.toString().contains(fragment),
    'reports "$fragment"',
  ),
);

void main() {
  test('reads a canonical workbook into a valid document', () {
    final doc = _read(_tabs());

    expect(doc.trackerId, 'trk-1');
    expect(doc.baseCurrency, 'EUR');
    expect(doc.currencies, {'EUR': 2, 'USD': 2});
    expect(doc.accounts['acc-1']!.name, 'Checking');
    expect(doc.accounts['acc-2']!.archived, isFalse);
    expect(doc.categories['cat-1']!.type, CategoryType.income);
    expect(doc.transactions.first.bookedOn, parseIsoDate('2026-03-01'));
    expect(doc.transactions.first.amountMinor, 320000);
    expect(doc.transactions.first.createdAt, isNotNull);
    expect(doc.transactions.last.tradeKey, 'trd-1');
    expect(doc.transactions.last.categoryKey, isNull);
    expect(doc.trades.single.units, Decimal.parse('2'));
    expect(doc.trades.single.side, TradeSide.buy);
    expect(doc.prices.single.priceMinor, 11000);
    expect(doc.fxRates.single.rate, Decimal.parse('1.08'));
    // An absent optional tab is an empty table, not a failure.
    expect(doc.imports, isEmpty);
    // The strongest check available: the parsed document satisfies the same
    // rules any other document must, including trade settlement matching.
    expect(validateTracker(doc), isEmpty);
  });

  test('reads portfolio membership, and a workbook written without it', () {
    // The canonical workbook above predates portfolios: it must still open, and
    // its investment account is simply unassigned.
    final before = _read(_tabs());
    expect(before.portfolios, isEmpty);
    expect(before.accounts['acc-2']!.portfolioKey, isNull);

    final tabs = _tabs();
    tabs['portfolios'] = [
      texts(['id', 'name']),
      texts(['pf-1', 'Retirement']),
    ];
    tabs['accounts'] = [
      texts(['id', 'name', 'type', 'currency', 'archived', 'portfolio_id']),
      texts(['acc-1', 'Checking', 'cash', 'EUR', 'false', '']),
      texts(['acc-2', 'Broker', 'brokerage', 'EUR', 'false', 'pf-1']),
    ];

    final doc = _read(tabs);
    expect(doc.portfolios['pf-1']!.name, 'Retirement');
    expect(doc.accounts['acc-2']!.portfolioKey, 'pf-1');
    expect(validateTracker(doc), isEmpty);
    expect(FinanceEngine.portfolioGroups(doc).single.accountIds, ['acc-2']);
  });

  test('reads the same workbook written with a namespace prefix', () {
    // `<s:row>` is as valid as `<row>`. A parser matching qualified names finds
    // no rows at all and reports a tracker with no money in it.
    final doc = readWorkbook(buildXlsx(_tabs(), prefix: 's'));

    expect(doc.accounts.length, 2);
    expect(doc.transactions.length, 2);
    expect(doc.transactions.first.amountMinor, 320000);
    expect(doc.transactions.first.bookedOn, parseIsoDate('2026-03-01'));
    expect(doc.trades.single.units, Decimal.parse('2'));
    expect(validateTracker(doc), isEmpty);
  });

  test('refuses a workbook whose declared sheet part is missing', () {
    // The transactions tab is declared but its part is gone: reading it as an
    // empty tab would report account balances that ignore every row it held.
    expect(
      () => readWorkbook(
        buildXlsx(_tabs(), omitParts: const {'xl/worksheets/sheet6.xml'}),
      ),
      throwsA(isA<WorkbookFormatException>()),
    );
  });

  test('refuses a number that only looks like an exact amount', () {
    // Rounded through a double this reads as 9007199254740990 and passes.
    final tabs = _tabs();
    tabs['transactions']![1][3] = number('9007199254740990.5');
    expect(_errorsOf(tabs), _reports('amount_minor "9007199254740990.5"'));
  });

  test('resolves date serials against the workbook date system', () {
    // The same day is a different serial in each system; reading one file's
    // serials with the other's epoch moves every date by 1,462 days.
    expect(
      _read(_tabs()).transactions.first.bookedOn,
      parseIsoDate('2026-03-01'),
    );

    final tabs = _tabs();
    tabs['transactions']![1][2] = dateSerial('44620');
    expect(
      _read(tabs, date1904: true).transactions.first.bookedOn,
      parseIsoDate('2026-03-01'),
    );
  });

  test('refuses a date serial carrying a time of day', () {
    // 46082.5 is noon on 1 March. Flooring it would report a date the workbook
    // never stated, from a timestamp whose timezone cannot be recovered.
    final tabs = _tabs();
    tabs['transactions']![1][2] = dateSerial('46082.5');
    expect(_errorsOf(tabs), _reports('booked_on must be an ISO date'));
  });

  test('refuses a time-formatted cell as a date', () {
    // Serial 1 under a time format is 24 hours, not 1 January 1900.
    final tabs = _tabs();
    tabs['transactions']![1][2] = timeSerial('1');
    expect(_errorsOf(tabs), _reports('booked_on must be an ISO date'));
  });

  test('keeps an amount under a colour or conditional number format', () {
    // `[Red]0` is a legacy amount format. Its bracket clause is not a date
    // component, so the cell stays an exact integer amount.
    final tabs = _tabs();
    tabs['transactions']![1][3] = customFormat('320000');
    expect(_read(tabs).transactions.first.amountMinor, 320000);

    // A custom date format still reads as a date.
    tabs['transactions']![1][3] = number('320000');
    tabs['transactions']![1][2] = customFormat('46082');
    expect(
      readWorkbook(buildXlsx(tabs, customNumberFormat: 'yyyy-mm-dd'))
          .transactions
          .first
          .bookedOn,
      parseIsoDate('2026-03-01'),
    );

    // A custom timestamp format does not.
    expect(
      _errorsOf(tabs, customNumberFormat: r'yyyy-mm-dd\ hh:mm'),
      _reports('booked_on must be an ISO date'),
    );
  });

  test('refuses a workbook carrying external links or macros', () {
    expect(
      () => readWorkbook(buildXlsx(_tabs(), externalLink: true)),
      throwsA(isA<WorkbookFormatException>()),
    );
    expect(
      () => readWorkbook(
        buildXlsx(_tabs(), extraParts: const {'xl/vbaProject.bin': 'macro'}),
      ),
      throwsA(isA<WorkbookFormatException>()),
    );
  });

  /// Replaces the `_meta` worksheet, the first tab of [_tabs], with [xml].
  List<int> withRawSheet(String xml) => buildXlsx(
    _tabs(),
    omitParts: const {'xl/worksheets/sheet1.xml'},
    extraParts: {'xl/worksheets/sheet1.xml': xml},
  );

  test('refuses a cell reference past the last column of a sheet', () {
    // The reader pads a row up to the reference, so an impossible one would
    // otherwise ask for a row of half a million cells out of a tiny file.
    expect(
      () => readWorkbook(
        withRawSheet(
          rawSheet('<row r="1"><c r="AAAAA1" t="inlineStr"><is><t>key</t>'
              '</is></c></row>'),
        ),
      ),
      throwsA(
        isA<WorkbookFormatException>().having(
          (e) => e.message,
          'message',
          contains('past the last column'),
        ),
      ),
    );
  });

  test('refuses a worksheet whose XML stops mid-sheet', () {
    // A truncated part is only discovered part-way through pulling its rows.
    // Reading the rows that did arrive would open a tracker missing whatever
    // the file stopped short of.
    expect(
      () => readWorkbook(
        withRawSheet(
          rawSheet(
            '<row r="1"><c r="A1" t="inlineStr"><is><t>key</t></is></c></row>'
            '<row r="2"><c r="A2" t="inlineStr"><is><t>format_version',
            closed: false,
          ),
        ),
      ),
      throwsA(
        isA<WorkbookFormatException>().having(
          (e) => e.message,
          'message',
          contains('is not valid XML'),
        ),
      ),
    );
  });

  test('refuses a worksheet part carrying a second root element', () {
    // Balanced tags alone do not make a part a document. A row past the
    // worksheet the file declares belongs to no sheet, and importing it would
    // add records the workbook itself does not hold.
    expect(
      () => readWorkbook(
        withRawSheet(
          '${rawSheet('<row r="1"><c r="A1" t="inlineStr"><is><t>key</t>'
              '</is></c></row>')}'
          '<row r="2"><c r="A2" t="inlineStr"><is><t>tracker_id</t></is>'
          '</c></row>',
        ),
      ),
      throwsA(
        isA<WorkbookFormatException>().having(
          (e) => e.message,
          'message',
          contains('is not valid XML'),
        ),
      ),
    );
  });

  test('keeps an empty shared string, which every later index counts on', () {
    // `<si/>` is one entry of the table. Dropping it moves every index past it
    // onto the wrong string, so a name, a currency, or an id silently becomes
    // another row's value.
    final tabs = _tabs();
    tabs['accounts'] = [
      texts(['id', 'name', 'type', 'currency', 'archived']),
      [text('acc-1'), sharedIndex('1'), ...texts(['cash', 'EUR', 'false'])],
      texts(['acc-2', 'Broker', 'brokerage', 'EUR', 'false']),
    ];
    final doc = readWorkbook(
      buildXlsx(
        tabs,
        omitParts: const {'xl/sharedStrings.xml'},
        extraParts: {
          'xl/sharedStrings.xml': rawSharedStrings(
            '<si/><si><t>Checking</t></si>',
          ),
        },
      ),
    );

    expect(doc.accounts['acc-1']!.name, 'Checking');
  });

  test('refuses a Boolean that is neither 0 nor 1', () {
    final tabs = _tabs();
    tabs['accounts']![1][4] = rawBoolean('2');
    expect(
      _errorsOf(tabs),
      _reports('archived holds a formula or a value with no exact text'),
    );
  });

  test('refuses a shared-string index outside the table', () {
    final tabs = _tabs();
    tabs['accounts']![1][1] = sharedIndex('-1');
    // Reported rather than thrown as a RangeError out of the parser.
    expect(
      _errorsOf(tabs),
      _reports('name holds a formula or a value with no exact text'),
    );
  });

  test('refuses the 1900 system serial that names no real day', () {
    // Serial 60 is 29 February 1900, a day that never existed.
    final tabs = _tabs();
    tabs['transactions']![1][2] = dateSerial('60');
    expect(_errorsOf(tabs), _reports('booked_on must be an ISO date'));
  });

  test('refuses a numeric decimal, a formula, and a bare date serial', () {
    final tabs = _tabs();
    tabs['trades']![1][5] = number('2');
    tabs['fx_rates']![1][3] = formula('=1/0.925');
    tabs['prices']![1][1] = number('46087');

    final errors = _errorsOf(tabs);
    expect(errors, _reports('units must be a text cell'));
    expect(errors, _reports('rate must be a text cell'));
    expect(errors, _reports('priced_on must be an ISO date'));
  });

  test('refuses an amount the platform cannot hold exactly', () {
    final tabs = _tabs();
    tabs['transactions']![1][3] = text('9007199254740992');
    expect(
      _errorsOf(tabs),
      _reports('amount_minor is outside the exact minor-unit range'),
    );
  });

  test('refuses a repeated canonical column and a repeated meta key', () {
    final tabs = _tabs();
    // A second amount_minor column: the row would otherwise report 1.
    tabs['transactions']![0].add(text('amount_minor'));
    tabs['transactions']![1].add(text('1'));
    tabs['_meta']!.add(texts(['base_currency', 'USD']));

    final errors = _errorsOf(tabs);
    expect(errors, _reports('Column amount_minor appears more than once'));
    expect(errors, _reports('base_currency]: Key appears more than once'));
  });

  test('refuses a formula as an identifier, a header, or workbook metadata', () {
    final tabs = _tabs();
    tabs['transactions']![1][0] = formula('="tx-"&1');
    tabs['trades']![0][6] = formula('="price_minor"');
    tabs['_meta']![4][1] = formula('="trk-"&1');

    final errors = _errorsOf(tabs);
    expect(errors, _reports('id holds a formula, not an identifier'));
    expect(errors, _reports('holds a formula, not a name'));
    expect(errors, _reports('formulas are not part of the format'));
  });

  test('refuses a timestamp that is not a real instant', () {
    final tabs = _tabs();
    // DateTime.parse would roll this forward to 3 March and store that.
    tabs['transactions']![1][14] = text('2026-02-31T09:30:00Z');
    expect(_errorsOf(tabs), _reports('is not an RFC 3339 UTC time'));

    tabs['transactions']![1][14] = text('2026-03-01 09:30:00');
    expect(_errorsOf(tabs), _reports('is not an RFC 3339 UTC time'));
  });

  test('refuses a missing tab, a missing column, and a duplicate id', () {
    final errors = _errorsOf({
      'currencies': [
        texts(['code']),
        texts(['EUR']),
      ],
      'accounts': [
        texts(['id', 'name', 'type', 'currency', 'archived']),
        texts(['acc-1', 'Checking', 'cash', 'EUR', 'false']),
        texts(['acc-1', 'Savings', 'cash', 'EUR', 'false']),
      ],
    });
    expect(errors, _reports('Workbook has no _meta tab'));
    expect(errors, _reports('Missing column minor_unit'));
    expect(errors, _reports('Duplicate id'));
  });

  test('refuses a file that is not a workbook at all', () {
    expect(
      () => readWorkbook([1, 2, 3, 4]),
      throwsA(isA<WorkbookFormatException>()),
    );
  });

  group('resource limits', () {
    /// Exceeding a limit rejects the load. Nothing truncates: a workbook read
    /// short would be a tracker missing records that still reports balances.
    void refuses(String limit, WorkbookLimits limits) => expect(
      () => readWorkbook(buildXlsx(_tabs()), limits: limits),
      throwsA(isA<WorkbookFormatException>()),
      reason: 'over the $limit limit',
    );

    test('refuse a workbook past any one of them', () {
      refuses('compressed size', const WorkbookLimits(compressedBytes: 64));
      refuses('archive entry', const WorkbookLimits(entries: 3));
      refuses('part size', const WorkbookLimits(partBytes: 64));
      refuses('decompressed total', const WorkbookLimits(totalBytes: 512));
      refuses('shared string', const WorkbookLimits(sharedStrings: 1));
      refuses('cell text', const WorkbookLimits(cellTextLength: 4));
      refuses('sheet row', const WorkbookLimits(rowsPerSheet: 2));
    });

    test('count the container directory, not the decoded archive', () {
      // The decoder parses and retains every directory record before it
      // returns, then collapses repeated filenames — so a count taken from the
      // archive it produced would read one file where the container declared
      // millions, after the memory was already spent. The refusal has to come
      // from the container, ahead of the decode, and this message is how the
      // test tells the two apart.
      expect(
        () => readWorkbook(
          buildXlsx(
            _tabs(),
            extraParts: {
              for (var i = 0; i < 200; i++) 'xl/spare$i.xml': '<spare/>',
            },
          ),
          limits: const WorkbookLimits(entries: 32),
        ),
        throwsA(
          isA<WorkbookFormatException>().having(
            (error) => error.message,
            'message',
            startsWith('Workbook directory has room for'),
          ),
        ),
      );
    });

    test('follow the ZIP64 directory the container declares', () {
      // The decoder takes its directory from the ZIP64 records whenever a
      // locator sits before the End of Central Directory record, replacing the
      // 32-bit fields whether or not they held the sentinel that announces
      // them. A container may therefore declare a small directory in the
      // 32-bit field and hand the decoder a huge one.
      // 64 is above what this workbook's own directory has room for and below
      // what the ZIP64 records claim, so only the claim can refuse it.
      const limits = WorkbookLimits(entries: 64);
      expect(readWorkbook(buildXlsx(_tabs()), limits: limits).trackerId,
          'trk-1');
      expect(
        () => readWorkbook(
          _withZip64Directory(buildXlsx(_tabs()), wholeFileIsDirectory: true),
          limits: limits,
        ),
        throwsA(
          isA<WorkbookFormatException>().having(
            (error) => error.message,
            'message',
            startsWith('Workbook directory has room for'),
          ),
        ),
      );
      // The same surgery restating the real directory still reads, so the
      // refusal above is the claim and not the rewritten tail.
      expect(
        readWorkbook(_withZip64Directory(buildXlsx(_tabs())), limits: limits)
            .trackerId,
        'trk-1',
      );
    });

    test('refuse an entry marked as a symbolic link', () {
      // The decoder decompresses a Unix link entry whole, to read its target,
      // while it is building the archive — before any byte limit can see it.
      // Marking the first entry is enough to prove the refusal happens; a
      // container attacking this marks every entry and points each at one
      // bomb.
      final zip = Uint8List.fromList(buildXlsx(_tabs()));
      final eocd = ByteData.sublistView(zip, zip.length - 22);
      final record = eocd.getUint32(16, Endian.little);
      ByteData.sublistView(zip, record)
        // Creator version 3 is how a Unix writer signs a record.
        ..setUint16(4, 0x0314, Endian.little)
        // File type 0xa000 in the mode the external attributes carry.
        ..setUint32(38, 0xa1ff0000, Endian.little);
      expect(
        () => readWorkbook(zip),
        throwsA(
          isA<WorkbookFormatException>().having(
            (error) => error.message,
            'message',
            contains('is a symbolic link'),
          ),
        ),
      );
    });

    test('refuse a directory record the container ends inside of', () {
      // 18 bytes: the signature, a huge directory size, and an offset whose
      // top half is off the end of the file. The decoder's scan reaches this
      // far and its file stream reads the missing bytes as zeros, so it can
      // select this record and parse a directory of whatever size it names,
      // from wherever the surviving offset bytes point.
      final trailing = ByteData(18)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint32(12, 0x7fffffff, Endian.little);
      expect(
        () => readWorkbook([
          ...buildXlsx(_tabs()),
          ...trailing.buffer.asUint8List(),
        ]),
        throwsA(
          isA<WorkbookFormatException>().having(
            (error) => error.message,
            'message',
            contains('ends inside a zip directory record'),
          ),
        ),
      );
    });

    test('refuse a container that ends with no directory record', () {
      final truncated = buildXlsx(_tabs());
      expect(
        () => readWorkbook(truncated.sublist(0, truncated.length - 22)),
        throwsA(isA<WorkbookFormatException>()),
      );
    });

    test('leave an ordinary workbook readable', () {
      expect(readWorkbook(buildXlsx(_tabs())).trackerId, 'trk-1');
    });
  });
}
