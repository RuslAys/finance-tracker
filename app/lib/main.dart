import 'package:flutter/material.dart';

import 'app.dart';
import 'features/sample_tracker.dart';
import 'features/tracker_controller.dart';

void main() {
  // No storage adapter exists yet, so the app opens the synthetic sample.
  runApp(
    FinanceTrackerApp(
      controller: TrackerController(
        sampleTracker(),
        priceProvider: sampleProvider,
        rateProvider: sampleProvider,
      ),
    ),
  );
}
