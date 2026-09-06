/// Display formatting for canonical values.
///
/// Money is formatted straight from its integer minor units: no double, no
/// locale-dependent parsing round trip.
library;

import '../domain/models.dart';

/// Formats minor units with the currency's own number of decimals.
///
/// `formatMinor(123456, 'EUR', 2)` is `123456` scaled to `1234.56 EUR`, and
/// `formatMinor(1234, 'JPY', 0)` is `1234 JPY`.
String formatMinor(Minor amountMinor, String currency, int minorUnit) {
  final digits = amountMinor.abs().toString().padLeft(minorUnit + 1, '0');
  final point = digits.length - minorUnit;
  final body = minorUnit == 0
      ? digits
      : '${digits.substring(0, point)}.${digits.substring(point)}';
  return '${amountMinor < 0 ? '-' : ''}$body $currency';
}
