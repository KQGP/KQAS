import 'package:intl/intl.dart';

import '../../database/tables/common.dart';

/// Quantities are stored as integers scaled by [kQtyScale] (1000).
/// A unit's `decimals` (0 for pieces, 3 for kg ...) limits what users may type.
class Qty {
  static int? parse(String input, {int decimals = 0}) {
    final s = input.trim().replaceAll(',', '.');
    final m = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(s);
    if (m == null) return null;
    final frac = m.group(2) ?? '';
    if (frac.length > decimals &&
        frac.substring(decimals).replaceAll('0', '').isNotEmpty) {
      return null; // more precision than the unit allows
    }
    final whole = int.tryParse(m.group(1)!);
    if (whole == null) return null;
    return whole * kQtyScale + int.parse(frac.padRight(3, '0'));
  }

  static String format(int scaled, {int decimals = 0}) {
    final neg = scaled < 0;
    final a = scaled.abs();
    final whole = NumberFormat('#,##0').format(a ~/ kQtyScale);
    if (decimals == 0) return '${neg ? '-' : ''}$whole';
    final frac = (a % kQtyScale).toString().padLeft(3, '0').substring(0, decimals);
    return '${neg ? '-' : ''}$whole.$frac';
  }
}

/// Money is stored as integer minor units (cents). No floating point maths.
class Money {
  static int? parse(String input) {
    final s = input.trim().replaceAll(',', '.');
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (m == null) return null;
    final whole = int.tryParse(m.group(1)!);
    if (whole == null) return null;
    return whole * 100 + int.parse((m.group(2) ?? '').padRight(2, '0'));
  }

  static String format(int minor) {
    final neg = minor < 0;
    final a = minor.abs();
    final whole = NumberFormat('#,##0').format(a ~/ 100);
    return '${neg ? '-' : ''}$whole.${(a % 100).toString().padLeft(2, '0')}';
  }

  /// Plain text for form fields (no thousands separators).
  static String toInput(int? minor) => minor == null
      ? ''
      : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}

class BarcodeUtil {
  static String? inferType(String code) {
    final digits = RegExp(r'^\d+$').hasMatch(code);
    if (digits) {
      switch (code.length) {
        case 13:
          return 'EAN-13';
        case 8:
          return 'EAN-8';
        case 12:
          return 'UPC-A';
        case 14:
          return 'ITF-14';
      }
    }
    return 'CODE-128';
  }
}
