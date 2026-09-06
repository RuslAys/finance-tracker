import 'package:finance_tracker/domain/decimal.dart';
import 'package:finance_tracker/domain/fx.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

FxRate _rate(
  String base,
  String quote,
  String rate, {
  String pricedOn = '2026-03-01',
  String provider = 'ecb',
}) => FxRate(
  baseCurrency: base,
  quoteCurrency: quote,
  pricedOn: parseIsoDate(pricedOn),
  rate: Decimal.parse(rate),
  provider: provider,
);

FxConverter _converter(List<FxRate> rates, {String provider = 'ecb'}) =>
    FxConverter(
      TrackerDocument(
        trackerId: 'trk-1',
        baseCurrency: 'EUR',
        currencies: const {'EUR': 2, 'USD': 2, 'JPY': 0, 'KWD': 3},
        fxRates: rates,
      ),
      provider: provider,
    );

final _asOf = parseIsoDate('2026-03-31');

void main() {
  test('converts one to one without a stored rate', () {
    expect(
      _converter(const []).convertMinor(1234, from: 'EUR', to: 'EUR', asOf: _asOf),
      1234,
    );
  });

  test('uses the direct pair and the reciprocal of the opposite pair', () {
    final fx = _converter([_rate('EUR', 'USD', '1.1')]);
    expect(fx.convertMinor(10000, from: 'EUR', to: 'USD', asOf: _asOf), 11000);
    // 100.00 USD / 1.1 = 90.9090..., rounded once to 90.91 EUR.
    expect(fx.convertMinor(10000, from: 'USD', to: 'EUR', asOf: _asOf), 9091);
  });

  test('scales between currencies with different minor units', () {
    final fx = _converter([_rate('EUR', 'JPY', '160')]);
    expect(fx.convertMinor(10000, from: 'EUR', to: 'JPY', asOf: _asOf), 16000);
    expect(fx.convertMinor(16000, from: 'JPY', to: 'EUR', asOf: _asOf), 10000);

    final kwd = _converter([_rate('EUR', 'KWD', '0.3')]);
    expect(kwd.convertMinor(10000, from: 'EUR', to: 'KWD', asOf: _asOf), 30000);
  });

  test('crosses two legs through the base currency', () {
    final fx = _converter([
      _rate('EUR', 'USD', '1.1'),
      _rate('EUR', 'JPY', '160'),
    ]);
    // 100.00 USD -> EUR -> JPY: 10000 x 160 / (1.1 x 100) = 14545.45...
    expect(fx.convertMinor(10000, from: 'USD', to: 'JPY', asOf: _asOf), 14545);
    // The chain stays rational: the effective rate is exactly 160 / 1.1.
    final rate = fx.effectiveRate('USD', 'JPY', _asOf)!;
    expect(rate.$1 * BigInt.from(11), rate.$2 * BigInt.from(1600));
  });

  test('takes the latest observation on or before the as-of date', () {
    final fx = _converter([
      _rate('EUR', 'USD', '1.1', pricedOn: '2026-01-01'),
      _rate('EUR', 'USD', '1.2', pricedOn: '2026-03-15'),
      _rate('EUR', 'USD', '9', pricedOn: '2026-04-01'),
    ]);
    expect(fx.convertMinor(10000, from: 'EUR', to: 'USD', asOf: _asOf), 12000);
    expect(
      fx.convertMinor(10000,
          from: 'EUR', to: 'USD', asOf: parseIsoDate('2026-02-01')),
      11000,
    );
  });

  test('reports an unavailable total instead of zero', () {
    final fx = _converter([_rate('EUR', 'USD', '1.1')]);
    expect(fx.convertMinor(10000, from: 'USD', to: 'KWD', asOf: _asOf), isNull);
    // A rate observed only after the as-of date is not usable either.
    expect(
      fx.convertMinor(10000,
          from: 'EUR', to: 'USD', asOf: parseIsoDate('2026-02-01')),
      isNull,
    );
  });

  test('never mixes providers', () {
    final fx = _converter([_rate('EUR', 'USD', '1.1', provider: 'bank')]);
    expect(fx.convertMinor(10000, from: 'EUR', to: 'USD', asOf: _asOf), isNull);
  });

  test('rounds an exact half away from zero', () {
    final fx = _converter([_rate('EUR', 'USD', '1.05')]);
    expect(fx.convertMinor(10, from: 'EUR', to: 'USD', asOf: _asOf), 11);
    expect(fx.convertMinor(-10, from: 'EUR', to: 'USD', asOf: _asOf), -11);
  });

  test('rejects a currency without its currencies row', () {
    expect(
      () => _converter(const [])
          .convertMinor(100, from: 'EUR', to: 'CHF', asOf: _asOf),
      throwsArgumentError,
    );
  });
}
