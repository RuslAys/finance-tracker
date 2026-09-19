/// Reads the SpreadsheetML parts of an `.xlsx` file into plain cell values.
///
/// This is deliberately a reader for the workbook the app itself defines: no
/// styling, merged cells, or charts. It exists rather than a spreadsheet
/// package because the money rules need what those packages hide — whether a
/// cell was stored as text or as a number, whether it holds a formula, and
/// which date system its serials count from.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

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

/// What one workbook may cost to read, from
/// `docs/flutter-architecture.md#large-workbooks`.
///
/// A ZIP states the uncompressed size of each part in its own directory, and a
/// small archive is free to state a small one and then decompress without
/// bound. Every byte limit here is therefore checked twice: once against the
/// declaration, so an honest oversized part is refused before it is expanded,
/// and once against the bytes actually produced, so a lying one is refused too.
///
/// Exceeding any limit rejects the load. Nothing here truncates: a workbook
/// read short would be a tracker that is missing records and still reports
/// balances, which is exactly the failure the limits exist to prevent.
///
/// The defaults are an Excel-shaped ceiling, not a target: a real tracker is
/// orders of magnitude smaller. They are settable so a check can exercise a
/// limit without building a gigabyte.
class WorkbookLimits {
  const WorkbookLimits({
    this.compressedBytes = 256 * 1024 * 1024,
    this.partBytes = 512 * 1024 * 1024,
    this.totalBytes = 1024 * 1024 * 1024,
    this.entries = 1024,
    this.sharedStrings = 2000000,
    this.cellTextLength = 32767,
    this.rowsPerSheet = 1048576,
  });

  /// Size of the container itself, before anything is decompressed.
  final int compressedBytes;

  /// Decompressed size of one part, and of every part added together.
  final int partBytes;
  final int totalBytes;

  /// Files the archive's directory has room for, read from the container
  /// before it is decoded and rounded up in the archive's favour. Set it well
  /// above the parts a workbook needs.
  final int entries;

  /// Entries in the shared-string table, which one sheet may reference many
  /// times over and which is held whole while the sheets are read.
  final int sharedStrings;

  /// Characters of one string, shared or inline. Excel's own cell limit.
  final int cellTextLength;

  /// `<row>` elements of one sheet. Excel's own sheet limit.
  final int rowsPerSheet;
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
  factory WorkbookParts.decode(
    List<int> bytes, {
    WorkbookLimits limits = const WorkbookLimits(),
  }) => WorkbookParts.decodeStream(InputMemoryStream(bytes), limits: limits);

  /// Reads the container from [input], which the caller closes.
  ///
  /// A caller holding a file passes an `InputFileStream` so that the compressed
  /// workbook is read from disk as it is needed rather than held whole.
  factory WorkbookParts.decodeStream(
    InputStream input, {
    WorkbookLimits limits = const WorkbookLimits(),
  }) {
    // Read before anything seeks: an archive stream's `length` is the bytes it
    // has left, so this is the container's size only while it sits at the start.
    final total = input.length;
    _within(
      total,
      limits.compressedBytes,
      'Workbook is larger than the ${limits.compressedBytes} byte limit',
    );

    // A zip states its directory in the last 64 KiB of the file. Without one
    // there is nothing to bound, and nothing to read either.
    final capacity = _directoryCapacity(input, total);
    if (capacity == null) {
      throw WorkbookFormatException(
        'Not a readable .xlsx container: it ends with no zip directory record',
      );
    }
    _within(
      capacity,
      limits.entries,
      'Workbook directory has room for $capacity files, more than the '
          '${limits.entries} allowed',
    );

    // The directory is read here rather than left to the decoder, because the
    // decoder expands the payload of every entry a Unix writer marked as a
    // symbolic link while it is still building the archive — before any byte
    // limit below can see it. Reading the directory first is what makes those
    // entries refusable. It costs a second parse of records the decoder parses
    // again; the capacity above is what keeps that bounded.
    final directory = ZipDirectory();
    try {
      directory.read(input);
    } catch (error) {
      throw WorkbookFormatException('Not a readable .xlsx container: $error');
    }
    for (final header in directory.fileHeaders) {
      if (_isSymbolicLink(header)) {
        throw WorkbookFormatException(
          'Workbook entry "${header.filename}" is a symbolic link; a workbook '
          'part is a file',
        );
      }
    }
    input.setPosition(0);

    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (error) {
      throw WorkbookFormatException('Not a readable .xlsx container: $error');
    }

    var totalBytes = 0;

    /// The decompressed text of a part, dropped from the archive's cache once
    /// read: the parts are large enough that keeping every one of them for the
    /// length of the load is most of the peak memory.
    String? text(String name) {
      final file = archive.findFile(name);
      if (file == null) return null;
      // ponytail: a part whose declared size lies is expanded once before its
      // real length is refused below. Bounding that too means decompressing
      // through a counting sink; do it if a measurement asks for it.
      _within(file.size, limits.partBytes, '$name declares more than the '
          '${limits.partBytes} byte limit');
      final bytes = file.readBytes();
      if (bytes == null) return null;
      _within(bytes.length, limits.partBytes,
          '$name is larger than the ${limits.partBytes} byte limit');
      totalBytes += bytes.length;
      _within(totalBytes, limits.totalBytes, 'Workbook decompresses to more '
          'than the ${limits.totalBytes} byte limit');
      final decoded = utf8.decode(bytes);
      file.clear();
      return decoded;
    }

    XmlDocument? part(String name) {
      final content = text(name);
      if (content == null) return null;
      try {
        return XmlDocument.parse(content);
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

    final strings = <String>[];
    for (final item in _subtrees(
      'xl/sharedStrings.xml',
      text('xl/sharedStrings.xml'),
      'si',
    )) {
      _within(strings.length + 1, limits.sharedStrings, 'Workbook holds more '
          'than the ${limits.sharedStrings} shared strings allowed');
      strings.add(
        _limited(_all(item, 't').map((t) => t.innerText).join(), limits),
      );
    }
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
      final content = text(path);
      if (content == null) {
        throw WorkbookFormatException('Sheet "$name" is missing its $path part');
      }
      sheets[name] = _rows(path, content, strings, dateStyles, date1904, limits);
    }
    return WorkbookParts(sheets);
  }

  /// Refuses the load when [value] is over [limit].
  static void _within(int value, int limit, String message) {
    if (value > limit) throw WorkbookFormatException(message);
  }

  /// Whether the decoder would expand this entry to read a link target.
  ///
  /// These are the two fields it tests: a creator version of 3 in the high
  /// byte, which is how a Unix writer signs a record, and a link file type in
  /// the mode the external attributes carry. An entry answering both is
  /// decompressed whole during the decode, whatever its size, so a container
  /// may mark every one of its entries this way and point each at the same
  /// payload. No part of a workbook is a link, so the container is refused.
  static bool _isSymbolicLink(ZipFileHeader header) =>
      (header.versionMadeBy >> 8) == 3 &&
      ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000;

  /// The most entries this container's directory can hold, or null when it
  /// ends with no directory record at all.
  ///
  /// Read before the decode, because the decode is what costs. `ZipDecoder`
  /// parses and retains a record for every central-directory entry, reads each
  /// one's local header, and copies each one's extra field, all before it
  /// returns anything — and it then collapses repeated filenames, so a
  /// directory of millions of entries under one name arrives as an archive of
  /// one file. Counting the decoded archive bounds neither the work nor the
  /// memory; only the directory does, and only ahead of time.
  ///
  /// A central-directory record is [_centralHeaderBytes] before its name, so
  /// the declared directory size is the ceiling on the records that fit in it,
  /// and the decoder reads neither past that size nor past the container, so a
  /// lying declaration bounds it as a truthful one does. The ceiling is
  /// conservative by roughly half, because a real record also carries a name:
  /// an archive is refused when its directory is merely large enough to hold
  /// more entries than are allowed, which is why the limit is set well above
  /// what a tracker workbook needs.
  ///
  /// [total] is the container's size, which the caller reads before the stream
  /// has moved: an archive stream reports the bytes left, not the bytes it has,
  /// so its `length` is not the file's once this has seeked. The position is
  /// left back at the start, where the decoder expects it.
  static int? _directoryCapacity(InputStream input, int total) {
    if (total < _eocdBytes) return null;
    try {
      // The record is within 64 KiB of the end — the furthest a comment can
      // push it — so the tail is read once and scanned in memory rather than
      // seeked over a byte at a time.
      final window = math.min(total, _eocdBytes + _maxCommentBytes);
      input.setPosition(total - window);
      final tail = ByteData.sublistView(input.readBytes(window).toUint8List());

      int? capacity;
      // Every candidate counts, not only the last one. The decoder runs its own
      // backward scan in 1 KiB chunks, and the three bytes straddling each
      // boundary fall in no chunk, so the record it settles on is not always
      // the one a single pass finds. The ceiling covers whichever it reaches,
      // which is why this scan runs to the last four bytes of the container
      // rather than to the last whole record.
      for (var at = window - 4; at >= 0; at--) {
        if (tail.getUint32(at, Endian.little) != _eocdSignature) continue;
        // A signature with no room for the rest of its record. The decoder's
        // own scan reads to within eight bytes of the end and its file stream
        // returns zeros past it, so it can settle on a record like this and
        // take a directory size from fields that run off the file, with an
        // offset the missing bytes zero out. Nothing observable bounds what it
        // would then parse, so the container is refused rather than measured.
        if (window - at < _eocdBytes) {
          throw WorkbookFormatException(
            'Not a readable .xlsx container: it ends inside a zip directory '
            'record',
          );
        }
        final zip64 = _zip64Directory(input, total - window + at, total);
        final size = zip64?.size ?? tail.getUint32(at + 12, Endian.little);
        final offset = zip64?.offset ?? tail.getUint32(at + 16, Endian.little);
        // However large the declaration, the decoder parses no further than the
        // container holds: it reads the directory as a subset, which a memory
        // stream clamps to the buffer and a file stream ends with zero bytes
        // that match no record signature.
        final reachable = math.min(size, math.max(0, total - offset));
        capacity = math.max(capacity ?? 0, reachable ~/ _centralHeaderBytes);
      }
      return capacity;
    } finally {
      input.setPosition(0);
    }
  }

  /// The directory the ZIP64 records name, or null when the 32-bit fields of
  /// the End of Central Directory record at [eocd] stand.
  ///
  /// This mirrors the decoder rather than the specification. `ZipDirectory`
  /// follows a ZIP64 locator whenever one sits immediately before the record,
  /// and replaces the size and offset it read with what it finds there —
  /// whether or not the 32-bit fields held the sentinel that is supposed to
  /// announce them. Reading ZIP64 only for the sentinel would let a container
  /// declare a small directory here and hand the decoder a huge one.
  static ({int size, int offset})? _zip64Directory(
    InputStream input,
    int eocd,
    int total,
  ) {
    if (eocd < _zip64LocatorBytes) return null;
    input.setPosition(eocd - _zip64LocatorBytes);
    if (input.readUint32() != _zip64LocatorSignature) return null;
    input.readUint32();
    final record = input.readUint64();
    // Past the end, or past what an integer holds: the decoder finds no
    // signature there either, and keeps its 32-bit fields, so this does too.
    if (record < 0 || record + _zip64EocdBytes > total) return null;
    input.setPosition(record);
    if (input.readUint32() != _zip64EocdSignature) return null;
    // Signature, record size, versions, disk numbers, and both entry counts.
    input.setPosition(record + 40);
    final size = input.readUint64();
    final offset = input.readUint64();
    // A value past the signed range is past the container, so it is clamped to
    // the container: unreadably large either way, and never negative.
    return (
      size: size < 0 ? total : size,
      offset: offset < 0 ? 0 : offset,
    );
  }

  /// Fixed part of an End of Central Directory record, before its comment.
  static const int _eocdBytes = 22;

  /// The longest comment that record's 16-bit length field can describe.
  static const int _maxCommentBytes = 0xffff;

  /// Fixed part of a central-directory record, before its name.
  static const int _centralHeaderBytes = 46;

  static const int _zip64LocatorBytes = 20;

  /// Fixed part of a ZIP64 End of Central Directory record, through the
  /// directory offset this reader needs.
  static const int _zip64EocdBytes = 56;

  static const int _eocdSignature = 0x06054b50;
  static const int _zip64LocatorSignature = 0x07064b50;
  static const int _zip64EocdSignature = 0x06064b50;

  /// Text no longer than one cell may hold, shared or inline.
  static String _limited(String text, WorkbookLimits limits) {
    _within(text.length, limits.cellTextLength, 'A string of ${text.length} '
        'characters is longer than the ${limits.cellTextLength} allowed');
    return text;
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

  /// The elements named [name] in [xml], one at a time.
  ///
  /// A worksheet is the one part that grows with the tracker, so it is pulled
  /// event by event: only the current subtree is built as a tree, rather than
  /// the whole part. [part] names the file in the error a malformed one raises.
  static Iterable<XmlElement> _subtrees(
    String part,
    String? xml,
    String name,
  ) sync* {
    if (xml == null) return;
    final events = <XmlEvent>[];
    var depth = 0;
    // A part is a document, not a fragment: a second root element past the one
    // the file declares is a damaged part, and the rows it carries belong to no
    // sheet, so reading them would add records the workbook does not hold.
    final iterator = parseEvents(
      xml,
      validateNesting: true,
      validateDocument: true,
    ).iterator;
    while (true) {
      // The parser reports a malformed part while it is being pulled, so every
      // step is guarded, not just the first.
      try {
        if (!iterator.moveNext()) return;
      } on XmlException catch (error) {
        throw WorkbookFormatException('$part is not valid XML: $error');
      }
      final event = iterator.current;
      if (depth == 0 &&
          (event is! XmlStartElementEvent || event.localName != name)) {
        continue;
      }
      // `<si/>` is an empty element, not an absent one: skipping it would shift
      // every shared-string index past it onto another string.
      events.add(event);
      if (event is XmlStartElementEvent && !event.isSelfClosing) {
        depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
      if (depth == 0) {
        final nodes = const XmlNodeDecoder().convert(events);
        events.clear();
        yield nodes.single as XmlElement;
      }
    }
  }

  static List<List<Cell>> _rows(
    String part,
    String xml,
    List<String> strings,
    Set<int> dateStyles,
    bool date1904,
    WorkbookLimits limits,
  ) {
    final rows = <List<Cell>>[];
    for (final row in _subtrees(part, xml, 'row')) {
      _within(rows.length + 1, limits.rowsPerSheet, '$part holds more than the '
          '${limits.rowsPerSheet} rows allowed');
      final cells = <Cell>[];
      for (final cell in _children(row, 'c')) {
        final column = _columnOf(cell.getAttribute('r'));
        // A writer omits empty cells, so position comes from the reference.
        while (column != null && cells.length < column) {
          cells.add(blankCell);
        }
        final value = _cell(cell, strings, dateStyles, date1904);
        _limited(value.text, limits);
        cells.add(value);
      }
      rows.add(cells);
    }
    return rows;
  }

  /// The last column a spreadsheet has, `XFD`.
  ///
  /// A reference past it names no cell, and the blank padding it would ask for
  /// is bounded by nothing but the text of the reference, so a small file could
  /// otherwise ask this reader for an unbounded row.
  static const int _lastColumn = 16383;

  /// Zero-based column of a cell reference such as `AB7`.
  static int? _columnOf(String? reference) {
    if (reference == null) return null;
    var column = 0;
    for (final unit in reference.codeUnits) {
      if (unit < 0x41 || unit > 0x5a) break;
      column = column * 26 + (unit - 0x40);
      if (column - 1 > _lastColumn) {
        throw WorkbookFormatException('Cell reference "$reference" is past the '
            'last column of a sheet');
      }
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
