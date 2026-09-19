import 'package:flutter/material.dart';

import 'app.dart';
import 'features/sample_tracker.dart';
import 'features/tracker_controller.dart';
import 'storage/xlsx_store.dart';

/// Path of the workbook to open at startup, from
/// `flutter run --dart-define=tracker=/path/finance-tracker.xlsx`.
///
/// Empty opens the synthetic sample; the user opens their own file from the
/// app's Open workbook action.
const _trackerPath = String.fromEnvironment('tracker');

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
          priceProvider: providerOf(
            priceProviderOverride,
            {for (final price in document.prices) price.provider},
            'price_provider',
          ),
          rateProvider: providerOf(
            rateProviderOverride,
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
