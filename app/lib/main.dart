import 'package:flutter/material.dart';

import 'app.dart';
import 'features/sample_tracker.dart';
import 'features/tracker_controller.dart';
import 'storage/xlsx_store.dart';

/// Path of the workbook to open, from
/// `flutter run --dart-define=tracker=/path/finance-tracker.xlsx`.
///
/// There is no file picker yet; empty opens the synthetic sample instead.
const _trackerPath = String.fromEnvironment('tracker');

/// Price and FX providers to report with, from
/// `--dart-define=price_provider=stooq --dart-define=rate_provider=ecb`.
const _priceProvider = String.fromEnvironment('price_provider');
const _rateProvider = String.fromEnvironment('rate_provider');

/// The provider a workbook's observations are read from.
///
/// A report never mixes providers, and the app must not pick one for the user:
/// with several in the file and none selected, nothing is reported until the
/// user names one. A workbook holding a single provider is unambiguous, so it
/// needs no flag.
String _provider(String selected, Set<String> present, String define) {
  if (selected.isNotEmpty) return selected;
  if (present.length <= 1) return present.firstOrNull ?? '';
  throw StateError(
    'Workbook holds observations from ${(present.toList()..sort()).join(', ')}. '
    'Pass --dart-define=$define=<provider> to choose one; mixing them is not '
    'permitted.',
  );
}

void main() async {
  if (_trackerPath.isEmpty) {
    runApp(
      FinanceTrackerApp(
        controller: TrackerController(
          sampleTracker(),
          priceProvider: sampleProvider,
          rateProvider: sampleProvider,
        ),
      ),
    );
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  try {
    final document = await openWorkbookFile(_trackerPath);
    runApp(
      FinanceTrackerApp(
        controller: TrackerController(
          document,
          source: _trackerPath,
          priceProvider: _provider(
            _priceProvider,
            {for (final price in document.prices) price.provider},
            'price_provider',
          ),
          rateProvider: _provider(
            _rateProvider,
            {for (final rate in document.fxRates) rate.provider},
            'rate_provider',
          ),
        ),
      ),
    );
  } catch (error) {
    // A workbook that cannot be read exactly opens as nothing at all: falling
    // back to the sample would show invented money under the user's file name.
    runApp(_WorkbookErrorApp(path: _trackerPath, error: error));
  }
}

class _WorkbookErrorApp extends StatelessWidget {
  const _WorkbookErrorApp({required this.path, required this.error});

  final String path;
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Cannot open workbook')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(path),
          const SizedBox(height: 16),
          SelectableText('$error'),
        ],
      ),
    ),
  );
}
