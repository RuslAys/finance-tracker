/// Exact decimal arithmetic for asset quantities and FX rates.
///
/// `docs/spreadsheet-format.md` forbids binary floating point anywhere in a
/// money or holdings path, so quantities travel as canonical decimal strings
/// and are computed here as `unscaled / 10^scale` over [BigInt].
library;

final BigInt _ten = BigInt.from(10);

BigInt _pow10(int exponent) => _ten.pow(exponent);

/// Divides exactly, rounding a tie away from zero.
///
/// This is the single rounding rule of the spreadsheet format: trade notionals
/// round half up (quantities and prices are positive there) and currency
/// conversion rounds an exact half away from zero.
BigInt roundedDivision(BigInt numerator, BigInt denominator) {
  if (denominator == BigInt.zero) {
    throw ArgumentError.value(denominator, 'denominator', 'Division by zero');
  }
  var n = numerator;
  var d = denominator;
  if (d.isNegative) {
    n = -n;
    d = -d;
  }
  final quotient = n ~/ d;
  final remainder = n.remainder(d);
  if (remainder.abs() * BigInt.two < d) return quotient;
  return remainder.isNegative ? quotient - BigInt.one : quotient + BigInt.one;
}

/// Largest minor-unit amount an `int` holds exactly on every Flutter target.
///
/// Web `int` is an IEEE-754 double, so a larger value would come back rounded.
/// The single limit keeps a tracker's results identical on web and native.
final BigInt maxExactMinor = BigInt.from(9007199254740991);

/// Whether a stored amount is inside the exactly representable range.
bool isExactMinor(int value) => BigInt.from(value).abs() <= maxExactMinor;

/// Converts an exact result to minor units, refusing to return a rounded one.
int toExactMinor(BigInt value) {
  if (value.abs() > maxExactMinor) {
    throw RangeError('$value exceeds the exact minor-unit range');
  }
  return value.toInt();
}

/// Adds minor-unit amounts, refusing a total the platform cannot hold exactly.
///
/// Two in-range amounts can sum out of range, and on web that sum would round
/// silently, so every accumulation of money goes through here.
int addMinor(int a, int b) => toExactMinor(BigInt.from(a) + BigInt.from(b));

/// Subtracts minor-unit amounts under the same exactness rule as [addMinor].
int subtractMinor(int a, int b) => toExactMinor(BigInt.from(a) - BigInt.from(b));

/// An exact decimal number, always held in canonical form.
///
/// `1.5`, `1.50` and `1.500` are the same value; `-0` is `0`.
class Decimal implements Comparable<Decimal> {
  const Decimal._(this._unscaled, this._scale);

  factory Decimal._canonical(BigInt unscaled, int scale) {
    var value = unscaled;
    var digits = scale;
    while (digits > 0 && value.remainder(_ten) == BigInt.zero) {
      value = value ~/ _ten;
      digits--;
    }
    return Decimal._(value, digits);
  }

  factory Decimal.fromInt(int value) => Decimal._(BigInt.from(value), 0);

  /// Parses a decimal string as written in a tracker cell.
  ///
  /// Trailing fractional zeroes and `-0` are accepted and normalize away.
  /// `+1`, `01`, `.85` and `1.` are rejected: readers never silently rewrite a
  /// value they cannot interpret exactly.
  factory Decimal.parse(String value) {
    final parsed = Decimal.tryParse(value);
    if (parsed == null) {
      throw FormatException('Not a decimal string', value);
    }
    return parsed;
  }

  static final RegExp _syntax = RegExp(r'^(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?$');

  static Decimal? tryParse(String value) {
    final match = _syntax.firstMatch(value);
    if (match == null) return null;
    final fraction = match.group(3) ?? '';
    final digits = BigInt.parse('${match.group(2)!}$fraction');
    return Decimal._canonical(
      match.group(1) == '-' ? -digits : digits,
      fraction.length,
    );
  }

  static final Decimal zero = Decimal._(BigInt.zero, 0);

  final BigInt _unscaled;
  final int _scale;

  bool get isZero => _unscaled == BigInt.zero;

  bool get isNegative => _unscaled.isNegative;

  BigInt _alignedTo(int scale) => _unscaled * _pow10(scale - _scale);

  Decimal operator +(Decimal other) {
    final scale = _scale > other._scale ? _scale : other._scale;
    return Decimal._canonical(_alignedTo(scale) + other._alignedTo(scale), scale);
  }

  Decimal operator -(Decimal other) {
    final scale = _scale > other._scale ? _scale : other._scale;
    return Decimal._canonical(_alignedTo(scale) - other._alignedTo(scale), scale);
  }

  Decimal operator *(Decimal other) =>
      Decimal._canonical(_unscaled * other._unscaled, _scale + other._scale);

  bool operator <(Decimal other) => compareTo(other) < 0;

  bool operator <=(Decimal other) => compareTo(other) <= 0;

  bool operator >(Decimal other) => compareTo(other) > 0;

  bool operator >=(Decimal other) => compareTo(other) >= 0;

  @override
  int compareTo(Decimal other) {
    final scale = _scale > other._scale ? _scale : other._scale;
    return _alignedTo(scale).compareTo(other._alignedTo(scale));
  }

  /// The exact value as `numerator / denominator`.
  ///
  /// FX resolution multiplies and inverts rates, so it needs the rational form
  /// rather than an intermediate decimal that would have to round.
  (BigInt, BigInt) get fraction => (_unscaled, _pow10(_scale));

  /// Multiplies by an integer amount, such as a price in minor units.
  Decimal timesInt(int value) =>
      Decimal._canonical(_unscaled * BigInt.from(value), _scale);

  /// Rounds to a whole number, ties away from zero.
  BigInt roundToBigInt() => roundedDivision(_unscaled, _pow10(_scale));

  /// Rounds to a whole number of minor units.
  int roundToMinor() => toExactMinor(roundToBigInt());

  /// Returns `amount * (this / total)`, rounded with ties away from zero.
  ///
  /// Used to split a FIFO lot's remaining cost when a sell consumes part of it.
  int proportionOf(int amount, Decimal total) => toExactMinor(
    roundedDivision(
      BigInt.from(amount) * _unscaled * _pow10(total._scale),
      total._unscaled * _pow10(_scale),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is Decimal && other._unscaled == _unscaled && other._scale == _scale;

  @override
  int get hashCode => Object.hash(_unscaled, _scale);

  /// Writes the canonical decimal string for a tracker cell.
  @override
  String toString() {
    if (_scale == 0) return _unscaled.toString();
    final digits = _unscaled.abs().toString().padLeft(_scale + 1, '0');
    final point = digits.length - _scale;
    final sign = _unscaled.isNegative ? '-' : '';
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }
}
