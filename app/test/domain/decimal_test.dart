import 'package:finance_tracker/domain/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsing', () {
    test('normalizes trailing zeroes and negative zero', () {
      expect(Decimal.parse('1.500').toString(), '1.5');
      expect(Decimal.parse('-0.0').toString(), '0');
      expect(Decimal.parse('1.50'), Decimal.parse('1.5'));
    });

    test('rejects non-canonical input', () {
      for (final value in ['.85', '1.', '+1', '01', '1,5', '', '1e3']) {
        expect(Decimal.tryParse(value), isNull, reason: value);
      }
    });
  });

  group('arithmetic', () {
    test('adds and subtracts across scales exactly', () {
      expect((Decimal.parse('0.1') + Decimal.parse('0.2')).toString(), '0.3');
      expect((Decimal.parse('1') - Decimal.parse('0.999')).toString(), '0.001');
    });

    test('compares across scales', () {
      expect(Decimal.parse('0.10') == Decimal.parse('0.1'), isTrue);
      expect(Decimal.parse('2') > Decimal.parse('1.999'), isTrue);
    });
  });

  group('rounding', () {
    test('rounds a trade notional with a tie away from zero', () {
      // 0.5 units at 333.33 rounds up, not to even.
      expect(Decimal.parse('0.5').timesInt(33333).roundToMinor(), 16667);
      expect(Decimal.parse('-0.5').timesInt(33333).roundToMinor(), -16667);
      expect(Decimal.parse('0.5').timesInt(2).roundToMinor(), 1);
    });

    test('splits a lot cost proportionally', () {
      // Two of five units carry two fifths of a 10000 minor-unit lot.
      expect(Decimal.parse('2').proportionOf(10000, Decimal.parse('5')), 4000);
      // A tie in the split also rounds away from zero.
      expect(Decimal.parse('0.5').proportionOf(101, Decimal.parse('1')), 51);
    });

    test('refuses a minor-unit amount it cannot represent exactly', () {
      // One over 2^53 - 1, the exact ceiling of a Flutter web int.
      expect(
        () => Decimal.parse('9007199254740992').roundToMinor(),
        throwsRangeError,
      );
      expect(Decimal.parse('9007199254740991').roundToMinor(), 9007199254740991);
    });

    test('rejects division by zero', () {
      expect(
        () => roundedDivision(BigInt.one, BigInt.zero),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
