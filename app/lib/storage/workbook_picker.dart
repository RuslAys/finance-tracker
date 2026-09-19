/// Platform file selection for the one open tracker.
///
/// Until this existed the workbook path came only from `--dart-define=tracker`,
/// so no user could open their own file. Selection is read-only: v1 has no
/// writer, and nothing here can damage what it opens.
///
/// A user-chosen path is `persistentAccess: revocable` under the
/// [storage model](../../docs/architecture.md#storage-model): the selection
/// grants access to this file for now, not a permission the app may assume
/// again later. Reopening asks the user again rather than storing a path and
/// failing quietly when the grant is gone.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import 'xlsx_store.dart';

/// The workbook the user chose, or null when they cancelled.
///
/// [name] is what the app shows as the source: on a browser there is no path
/// to show, and on a phone the path is a sandbox copy that means nothing to the
/// user.
typedef PickedWorkbook = ({String name, TrackerDocument document});

/// Asks the user for a workbook and reads it.
///
/// A browser gives bytes and never a `dart:io` path, so it reads through
/// [readWorkbook] and holds the whole compressed workbook in memory — the
/// retention [openWorkbookFile] exists to avoid. [limits] is what bounds it,
/// which is why web selection ships with them rather than before them. CPU work
/// stays on the browser's main thread until a Web Worker is added; `compute()`
/// does not move it.
///
/// Throws whatever reading throws: a workbook that cannot be read exactly is
/// reported, and the tracker already open is left alone.
Future<PickedWorkbook?> pickWorkbook({
  WorkbookLimits limits = const WorkbookLimits(),
}) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Tracker workbook', extensions: ['xlsx']),
    ],
  );
  if (file == null) return null;
  return (
    name: kIsWeb ? file.name : file.path,
    document: kIsWeb
        ? readWorkbook(await file.readAsBytes(), limits: limits)
        : await openWorkbookFile(file.path, limits: limits),
  );
}
