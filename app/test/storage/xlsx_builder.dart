/// Builds `.xlsx` bytes for the storage tests.
///
/// Small on purpose: enough SpreadsheetML to exercise the reader's cell rules —
/// inline and shared strings, numbers, booleans, formulas, date-formatted
/// serials, and either date system — without a spreadsheet library standing
/// between the test and the bytes.
library;

import 'dart:convert';

import 'package:archive/archive.dart';

typedef TestCell = ({String kind, String value});

TestCell text(String value) => (kind: 'inline', value: value);

TestCell shared(String value) => (kind: 'shared', value: value);

TestCell number(String value) => (kind: 'number', value: value);

TestCell boolean(bool value) => (kind: 'bool', value: value ? '1' : '0');

TestCell formula(String value) => (kind: 'formula', value: value);

/// A number carrying a date format, which is what a spreadsheet writes when a
/// user types a date into a cell.
TestCell dateSerial(String serial) => (kind: 'date', value: serial);

/// A number carrying a time format, such as a duration or a clock time.
TestCell timeSerial(String serial) => (kind: 'time', value: serial);

/// A Boolean cell holding exactly what is given, valid or not.
TestCell rawBoolean(String value) => (kind: 'bool', value: value);

/// A shared-string reference holding exactly the index given, valid or not.
TestCell sharedIndex(String index) => (kind: 'sharedIndex', value: index);

/// A number carrying the workbook's custom number format, style 3.
TestCell customFormat(String value) => (kind: 'custom', value: value);

List<TestCell> texts(List<String> values) => [for (final v in values) text(v)];

const _mainNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

String _escape(String value) => const HtmlEscape().convert(value);

/// Column reference such as `A`, `Z`, `AA`.
String columnName(int index) {
  var name = '';
  var remaining = index;
  while (true) {
    name = String.fromCharCode(0x41 + remaining % 26) + name;
    if (remaining < 26) return name;
    remaining = remaining ~/ 26 - 1;
  }
}

List<int> buildXlsx(
  Map<String, List<List<TestCell>>> tabs, {
  bool date1904 = false,
  String prefix = '',
  Set<String> omitParts = const {},
  Map<String, String> extraParts = const {},
  String customNumberFormat = '[Red]0',
  bool externalLink = false,
}) {
  final strings = <String>[];
  final sheetParts = <String>[];

  // SpreadsheetML is as valid with a namespace prefix as with a default
  // namespace, so the tests can write either.
  String tag(String name) => prefix.isEmpty ? name : '$prefix:$name';
  final namespace = prefix.isEmpty
      ? 'xmlns="$_mainNamespace"'
      : 'xmlns:$prefix="$_mainNamespace"';

  for (final tab in tabs.entries) {
    final rows = StringBuffer();
    var rowNumber = 1;
    for (final row in tab.value) {
      rows.write('<${tag('row')} r="$rowNumber">');
      for (var column = 0; column < row.length; column++) {
        final cell = row[column];
        final reference = '${columnName(column)}$rowNumber';
        final c = tag('c');
        final v = tag('v');
        rows.write(switch (cell.kind) {
          'inline' =>
            '<$c r="$reference" t="inlineStr"><${tag('is')}><${tag('t')}>'
                '${_escape(cell.value)}</${tag('t')}></${tag('is')}></$c>',
          'shared' =>
            '<$c r="$reference" t="s"><$v>'
                '${strings.contains(cell.value) ? strings.indexOf(cell.value) : (strings..add(cell.value)).length - 1}'
                '</$v></$c>',
          'number' => '<$c r="$reference"><$v>${cell.value}</$v></$c>',
          'bool' => '<$c r="$reference" t="b"><$v>${cell.value}</$v></$c>',
          'sharedIndex' => '<$c r="$reference" t="s"><$v>${cell.value}</$v></$c>',
          // Styles 1 and 2 are the date and time formats in styles.xml below.
          'date' => '<$c r="$reference" s="1"><$v>${cell.value}</$v></$c>',
          'time' => '<$c r="$reference" s="2"><$v>${cell.value}</$v></$c>',
          'custom' => '<$c r="$reference" s="3"><$v>${cell.value}</$v></$c>',
          'formula' =>
            '<$c r="$reference" t="str"><${tag('f')}>${_escape(cell.value)}'
                '</${tag('f')}><$v>${_escape(cell.value)}</$v></$c>',
          _ => throw ArgumentError('Unknown cell kind ${cell.kind}'),
        });
      }
      rows.write('</${tag('row')}>');
      rowNumber++;
    }
    sheetParts.add(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<${tag('worksheet')} $namespace>'
      '<${tag('sheetData')}>$rows</${tag('sheetData')}>'
      '</${tag('worksheet')}>',
    );
  }

  final names = tabs.keys.toList();
  final workbook = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write(
      '<${tag('workbook')} $namespace '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    // Single-quoted on purpose: a reader that pattern-matches the raw XML text
    // instead of parsing it misses this and silently shifts every date.
    ..write(
      date1904
          ? "<${tag('workbookPr')} date1904='1'/>"
          : '<${tag('workbookPr')}/>',
    )
    ..write('<${tag('sheets')}>');
  for (var i = 0; i < names.length; i++) {
    workbook.write(
      '<${tag('sheet')} name="${_escape(names[i])}" sheetId="${i + 1}" '
      'r:id="rId${i + 1}"/>',
    );
  }
  workbook.write('</${tag('sheets')}></${tag('workbook')}>');

  final rels = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
  for (var i = 0; i < names.length; i++) {
    rels.write(
      '<Relationship Id="rId${i + 1}" Target="worksheets/sheet${i + 1}.xml" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/>',
    );
  }
  if (externalLink) {
    rels.write(
      '<Relationship Id="rIdExt" Target="externalLinks/externalLink1.xml" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/externalLink"/>',
    );
  }
  rels.write('</Relationships>');

  final archive = Archive();
  void add(String name, String content) {
    if (omitParts.contains(name)) return;
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="xml" ContentType="application/xml"/></Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Target="xl/workbook.xml" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"/>'
    '</Relationships>',
  );
  add('xl/workbook.xml', '$workbook');
  add('xl/_rels/workbook.xml.rels', '$rels');
  add(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<${tag('styleSheet')} $namespace>'
    // Style 0 is general, style 1 is built-in date format 14, style 2 is
    // built-in time format 20 (h:mm), style 3 is the custom format above.
    '<${tag('numFmts')} count="1"><${tag('numFmt')} numFmtId="164" '
    'formatCode="${_escape(customNumberFormat)}"/></${tag('numFmts')}>'
    '<${tag('cellXfs')} count="4"><${tag('xf')} numFmtId="0"/>'
    '<${tag('xf')} numFmtId="14"/><${tag('xf')} numFmtId="20"/>'
    '<${tag('xf')} numFmtId="164"/>'
    '</${tag('cellXfs')}>'
    '</${tag('styleSheet')}>',
  );
  add(
    'xl/sharedStrings.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<${tag('sst')} $namespace>'
    '${strings.map((s) => '<${tag('si')}><${tag('t')}>${_escape(s)}'
        '</${tag('t')}></${tag('si')}>').join()}'
    '</${tag('sst')}>',
  );
  for (var i = 0; i < sheetParts.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', sheetParts[i]);
  }
  extraParts.forEach(add);
  return ZipEncoder().encode(archive);
}
