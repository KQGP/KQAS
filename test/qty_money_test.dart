import 'package:flutter_test/flutter_test.dart';
import 'package:kqas/core/utilities/qty_money.dart';

void main() {
  test('Qty parses and formats with unit precision', () {
    expect(Qty.parse('5'), 5000);
    expect(Qty.parse('2.5', decimals: 3), 2500);
    expect(Qty.parse('2.5'), isNull); // pieces cannot be fractional
    expect(Qty.parse('2.0'), 2000); // trailing zeros are fine
    expect(Qty.parse('abc'), isNull);
    expect(Qty.parse('-1'), isNull);
    expect(Qty.format(1234000), '1,234');
    expect(Qty.format(2500, decimals: 3), '2.500');
  });

  test('Money is exact integer minor units', () {
    expect(Money.parse('12.50'), 1250);
    expect(Money.parse('0.1'), 10);
    expect(Money.parse('1.234'), isNull);
    expect(Money.format(123456), '1,234.56');
    expect(Money.parse('19.99')! * 3, 5997); // no floating point drift
  });
}
