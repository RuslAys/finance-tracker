/// Reads the SpreadsheetML parts of an `.xlsx` file into plain cell values.
///
/// This is deliberately a reader for the workbook the app itself defines: no
/// styling, merged cells, or charts. It exists rather than a spreadsheet
/// package because the money rules need what those packages hide — whether a
/// cell was stored as text or as a number, whether it holds a formula, and
/// which date system its serials count from.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// What the workbook stored a cell as, which decides what it may be read as.
///
/// `opaque` covers formulas, error values, and numbers whose exact meaning
/// cannot be recovered, so no canonical field accepts them.
enum CellKind { text, number, boolean, date, opaque }

typedef Cell = ({String text, CellKind kind});

const Cell blankCell = (text: '', kind: CellKind.text);

/// Thrown when the file is not a readable `.xlsx` container at all.
class WorkbookFormatException implements Exception {
  WorkbookFormatException(this.message);

  final String message;

  @override
  String toString() => 'WorkbookFormatException: $message';
}

/// One workbook's tabs, each a list of rows of cells.
class WorkbookParts {
  WorkbookParts(this.sheets);

  /// Tab name to rows. A row is indexed by column, gaps included as blanks.
  final Map<String, List<List<Cell>>> sheets;

  /// Built-in number formats that render a calendar date and nothing else.
  ///
  /// 18-21, 22, and 45-47 are times, date-times, and durations. Their serials
  /// carry a time of day whose timezone cannot be recovered, so they are not
  /// dates: reading one as a date would turn a duration of one day into
  /// 1 January 1900.
  static const Set<int> _builtinDateFormats = {14, 15, 16, 17};

  /// Parses the parts this reader needs: the workbook, its relationships,
  /// shared strings, number formats, and every sheet.
  factory WorkbookParts.decode(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw WorkbookFormatException('Not a readable .xlsx container: $error');
    }

    XmlDocument? part(String name) {
      final bytes = archive.findFile(name)?.readBytes();
      if (bytes == null) return null;
      try {
        return XmlDocument.parse(utf8.decode(bytes));
      } on XmlException catch (error) {
        throw WorkbookFormatException('$name is not valid XML: $error');
      }
    }

    final workbook = part('xl/workbook.xml');
    if (workbook == null) {
      throw WorkbookFormatException('Missing xl/workbook.xml');
    }

    // Excel for Mac wrote serials counted from 1904. Reading them against the
    // 1900 epoch shifts every date 1,462 days, which would move transactions
    // between reporting periods, so the declared system decides the epoch.
    final date1904 = _isTrue(
      _all(workbook, 'workbookPr').firstOrNull?.getAttribute('date1904'),
    );

    // A tracker carries no macros and no external links: both make its numbers
    // depend on something outside the file, which the format forbids so the
    // same workbook reads the same everywhere.
    if (archive.findFile('xl/vbaProject.bin') != null) {
      throw WorkbookFormatException('Workbook contains macros');
    }
    if (_all(workbook, 'externalReferences').isNotEmpty) {
      throw WorkbookFormatException('Workbook references an external workbook');
    }

    final targets = <String, String>{};
    for (final relation
        in _allIn(part('xl/_rels/workbook.xml.rels'), 'Relationship')) {
      if ((relation.getAttribute('Type') ?? '').endsWith('/externalLink')) {
        throw WorkbookFormatException('Workbook links to an external workbook');
      }
      final id = relation.getAttribute('Id');
      final target = relation.getAttribute('Target');
      if (id != null && target != null) targets[id] = target;
    }

    final strings = [
      for (final item in _allIn(part('xl/sharedStrings.xml'), 'si'))
        _all(item, 't').map((t) => t.innerText).join(),
    ];
    final dateStyles = _dateStyles(part('xl/styles.xml'));

    final sheets = <String, List<List<Cell>>>{};
    for (final sheet in _all(workbook, 'sheet')) {
      // A declared tab whose part is absent is a damaged container, not an
      // empty tab: reading it as empty would drop every transaction it held and
      // still report a balance.
      final name = sheet.getAttribute('name');
      final id =
          sheet.getAttribute('r:id') ??
          sheet.getAttribute('id', namespaceUri: '*');
      if (name == null || id == null) {
        throw WorkbookFormatException('A sheet declares no name or relationship');
      }
      final target = targets[id];
      if (target == null) {
        throw WorkbookFormatException('Sheet "$name" points at missing $id');
      }
      final path = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst('./', '')}';
      final document = part(path);
      if (document == null) {
        throw WorkbookFormatException('Sheet "$name" is missing its $path part');
      }
      sheets[name] = _rows(document, strings, dateStyles, date1904);
    }
    return WorkbookParts(sheets);
  }

  /// Descendants of [node] by local name.
  ///
  /// SpreadsheetML is equally valid written as `<row>` with a default namespace
  /// or `<s:row>` with a prefix, so every lookup ignores the prefix. Matching
  /// qualified names instead would read a prefixed workbook as an empty one.
  static Iterable<XmlElement> _all(XmlNode node, String name) =>
      node.findAllElements(name, namespaceUri: '*');

  static Iterable<XmlElement> _allIn(XmlNode? node, String name) =>
      node == null ? const [] : _all(node, name);

  /// Direct children of [element] by local name.
  static Iterable<XmlElement> _children(XmlElement element, String name) =>
      element.findElements(name, namespaceUri: '*');

  static bool _isTrue(String? value) =>
      value == '1' || value?.toLowerCase() == 'true';

  /// Style indexes whose number format makes a numeric cell a date.
  static Set<int> _dateStyles(XmlDocument? styles) {
    if (styles == null) return const {};
    final custom = <int, String>{};
    for (final format in _all(styles, 'numFmt')) {
      final id = int.tryParse(format.getAttribute('numFmtId') ?? '');
      final code = format.getAttribute('formatCode');
      if (id != null && code != null) custom[id] = code;
    }

    final dateStyles = <int>{};
    final cellXfs = _all(styles, 'cellXfs').firstOrNull;
    var index = 0;
    for (final xf in cellXfs == null ? const <XmlElement>[] : _children(cellXfs, 'xf')) {
      final id = int.tryParse(xf.getAttribute('numFmtId') ?? '') ?? 0;
      final code = custom[id];
      if (_builtinDateFormats.contains(id) ||
          (code != null && _looksLikeADate(code))) {
        dateStyles.add(index);
      }
      index++;
    }
    return dateStyles;
  }

  /// Whether a custom number format renders a calendar date and no time.
  ///
  /// Literal text in quotes and bracketed conditions are ignored first, so a
  /// currency format is not mistaken for one. A format carrying hours or
  /// seconds is a timestamp, not a date, and is refused for the same reason as
  /// the built-in time formats.
  static bool _looksLikeADate(String code) {
    final format = code
        .replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '')
        .toLowerCase();
    return RegExp(r'[yd]|m{3,}').hasMatch(format) &&
        !RegExp(r'[hs]|am/pm|a/p').hasMatch(format);
  }

  static List<List<Cell>> _rows(
    XmlDocument sheet,
    List<String> strings,
    Set<int> dateStyles,
    bool date1904,
  ) {
    final rows = <List<Cell>>[];
    for (final row in _all(sheet, 'row')) {
      final cells = <Cell>[];
      for (final cell in _children(row, 'c')) {
        final column = _columnOf(cell.getAttribute('r'));
        // A writer omits empty cells, so position comes from the reference.
        while (column != null && cells.length < column) {
          cells.add(blankCell);
        }
        cells.add(_cell(cell, strings, dateStyles, date1904));
      }
      rows.add(cells);
    }
    return rows;
  }

  /// Zero-based column of a cell reference such as `AB7`.
  static int? _columnOf(String? reference) {
    if (reference == null) return null;
    var column = 0;
    for (final unit in reference.codeUnits) {
      if (unit < 0x41 || unit > 0x5a) break;
      column = column * 26 + (unit - 0x40);
    }
    return column == 0 ? null : column - 1;
  }

  static Cell _cell(
    XmlElement cell,
    List<String> strings,
    Set<int> dateStyles,
    bool date1904,
  ) {
    // The format forbids formulas outright, and a cached result cannot be told
    // apart from a stored value once read, so the cell is refused here.
    if (_children(cell, 'f').isNotEmpty) {
      return (text: cell.innerText.trim(), kind: CellKind.opaque);
    }

    final type = cell.getAttribute('t') ?? 'n';
    final value = _children(cell, 'v').firstOrNull?.innerText ?? '';
    switch (type) {
      case 's':
        final index = int.tryParse(value);
        final inRange = index != null && index >= 0 && index < strings.length;
        return inRange
            ? (text: strings[index].trim(), kind: CellKind.text)
            : (text: value, kind: CellKind.opaque);
      case 'inlineStr':
        return (
          text: _children(cell, 'is')
              .expand((inline) => _all(inline, 't'))
              .map((t) => t.innerText)
              .join()
              .trim(),
          kind: CellKind.text,
        );
      case 'str':
        return (text: value.trim(), kind: CellKind.text);
      case 'b':
        // Only 0 and 1 are Booleans. Anything else is a value this reader
        // cannot interpret, and reading it as false would invent an answer.
        return switch (value) {
          '1' => (text: 'true', kind: CellKind.boolean),
          '0' => (text: 'false', kind: CellKind.boolean),
          _ => (text: value, kind: CellKind.opaque),
        };
      case 'd':
        return (text: value.trim(), kind: CellKind.text);
      case 'e':
        return (text: value.trim(), kind: CellKind.opaque);
      default:
        if (value.isEmpty) return blankCell;
        final style = int.tryParse(cell.getAttribute('s') ?? '') ?? -1;
        if (dateStyles.contains(style)) {
          final date = _dateOfSerial(value, date1904);
          return date == null
              ? (text: value, kind: CellKind.opaque)
              : (text: date, kind: CellKind.date);
        }
        return (text: _numberText(value), kind: CellKind.number);
    }
  }

  /// A whole date serial resolved against the workbook's own epoch.
  ///
  /// A fractional serial is a time of day, not a date. Truncating it would
  /// invent a date from a timestamp whose timezone and precision cannot be
  /// recovered, which `docs/spreadsheet-format.md` refuses, so it is rejected
  /// along with anything else that is not a whole count of days.
  ///
  /// Serial 60 is refused too: the 1900 system contains a 29 February 1900 that
  /// never existed, so that one value names no real day.
  static String? _dateOfSerial(String value, bool date1904) {
    final digits = _wholeNumber.firstMatch(value)?.group(1);
    final days = digits == null ? null : int.tryParse(digits);
    if (days == null || days < 0) return null;
    if (!date1904 && days == 60) return null;
    // Serial 1 is 1900-01-01 or 1904-01-01. The 1900 system counts a day that
    // never existed, so every serial past it is one day further along than the
    // real calendar.
    final epoch = date1904
        ? DateTime.utc(1904, 1, 1)
        : DateTime.utc(1899, 12, 31);
    final offset = date1904 || days < 60 ? days : days - 1;
    final date = epoch.add(Duration(days: offset));
    return date.toIso8601String().substring(0, 10);
  }

  static final RegExp _wholeNumber = RegExp(r'^(-?\d+)(?:\.0+)?$');

  /// A whole number keeps its integer form, so a minor amount stored as a
  /// number reads as an exact integer rather than `1234.0`.
  ///
  /// The digits are read as written, never through a `double`: at the top of
  /// the exact range `9007199254740990.5` rounds to an even integer, and a
  /// malformed amount would arrive looking like a valid one. Anything else,
  /// including scientific notation, is passed through unchanged for the field
  /// parser to refuse.
  static String _numberText(String value) =>
      _wholeNumber.firstMatch(value)?.group(1) ?? value;
}
