/// Cross-currency conversion over stored `fx_rates`.
///
/// The resolution order and the rounding rule are fixed by
/// `docs/spreadsheet-format.md`: identity, direct, reciprocal, then two legs
/// through the tracker's base currency, all from one provider. Rates stay
/// rational until the single final rounding, so no intermediate decimal rate is
/// ever materialized.
library;

import 'decimal.dart';
import 'models.dart';

/// An exact rate as `numerator / denominator` of quote units per base unit.
typedef RateFraction = (BigInt, BigInt);

class FxConverter {
  /// Indexes the rows of one `provider`; another provider's rows are invisible.
  FxConverter(TrackerDocument doc, {required this.provider})
      : _baseCurrency = doc.baseCurrency,
        _minorUnits = doc.currencies {
    for (final rate in doc.fxRates) {
      if (rate.provider != provider) continue;
      _byPair
          .putIfAbsent(_pairKey(rate.baseCurrency, rate.quoteCurrency), () => [])
          .add(rate);
    }
  }

  final String provider;
  final String _baseCurrency;
  final Map<String, int> _minorUnits;
  final Map<String, List<FxRate>> _byPair = {};

  static String _pairKey(String base, String quote) => '$base|$quote';

  /// Latest observation of one stored pair on or before [asOf].
  // ponytail: linear scan per lookup; sort per pair if rate tables get large.
  RateFraction? _observed(String base, String quote, DateTime asOf) {
    FxRate? best;
    for (final rate in _byPair[_pairKey(base, quote)] ?? const <FxRate>[]) {
      if (rate.pricedOn.isAfter(asOf)) continue;
      // A rate the schema rejects is not an observation. A zero or negative one
      // has no reciprocal either, so a leg using it would invert a real amount.
      if (rate.rate <= Decimal.zero) continue;
      if (best == null || rate.pricedOn.isAfter(best.pricedOn)) best = rate;
    }
    return best?.rate.fraction;
  }

  /// One leg: the stored pair, otherwise the reciprocal of the opposite pair.
  RateFraction? _leg(String from, String to, DateTime asOf) {
    final direct = _observed(from, to, asOf);
    if (direct != null) return direct;
    final reciprocal = _observed(to, from, asOf);
    return reciprocal == null ? null : (reciprocal.$2, reciprocal.$1);
  }

  /// The effective rate from [from] to [to], or `null` when no leg resolves.
  ///
  /// A caller must not treat `null` as zero: the converted total is unavailable.
  RateFraction? effectiveRate(String from, String to, DateTime asOf) {
    if (from == to) return (BigInt.one, BigInt.one);
    final direct = _leg(from, to, asOf);
    if (direct != null) return direct;

    // The only permitted triangulation is through the tracker's base currency.
    if (from == _baseCurrency || to == _baseCurrency) return null;
    final first = _leg(from, _baseCurrency, asOf);
    if (first == null) return null;
    final second = _leg(_baseCurrency, to, asOf);
    if (second == null) return null;
    return (first.$1 * second.$1, first.$2 * second.$2);
  }

  /// Converts minor units between currencies, rounding once, ties away from
  /// zero. Returns `null` when the rate chain is incomplete.
  Minor? convertMinor(
    Minor amountMinor, {
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    final fromUnit = _minorUnits[from];
    final toUnit = _minorUnits[to];
    if (fromUnit == null || toUnit == null) {
      // A validated document always carries both rows; reaching here means the
      // caller skipped validation, which is a bug rather than a missing rate.
      throw ArgumentError('Currency ${fromUnit == null ? from : to} has no '
          'currencies row');
    }
    // Zero is zero at every rate, so a zero amount is exactly known even where
    // no observation exists. Reporting it as unavailable would make an empty
    // foreign account hide the totals of every account beside it.
    if (amountMinor == 0) return 0;

    final rate = effectiveRate(from, to, asOf);
    if (rate == null) return null;

    final scale = BigInt.from(10);
    return toExactMinor(
      roundedDivision(
        BigInt.from(amountMinor) * rate.$1 * scale.pow(toUnit),
        rate.$2 * scale.pow(fromUnit),
      ),
    );
  }
}
