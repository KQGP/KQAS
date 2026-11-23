import '../utilities/qty_money.dart';

abstract class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

class InvalidQuantityException extends AppException {
  const InvalidQuantityException() : super('Quantity must be greater than zero.');
}

class ReasonRequiredException extends AppException {
  ReasonRequiredException(String label) : super('A reason is required for "$label".');
}

class InsufficientStockException extends AppException {
  InsufficientStockException({
    required this.requested,
    required this.physical,
    required this.reserved,
    required int decimals,
  })  : available = physical - reserved,
        shortage = requested - (physical - reserved),
        super('Insufficient stock. You need ${Qty.format(requested, decimals: decimals)} units, '
            'but only ${Qty.format(physical - reserved, decimals: decimals)} are available. '
            'Shortage: ${Qty.format(requested - (physical - reserved), decimals: decimals)} units.');

  final int requested;
  final int physical;
  final int reserved;
  final int available;
  final int shortage;
}

class NegativeOverrideNotAllowedException extends AppException {
  const NegativeOverrideNotAllowedException(super.message);
}

class DuplicateBarcodeException extends AppException {
  DuplicateBarcodeException(String barcode, String productName)
      : super('Barcode $barcode is already assigned to "$productName".');
}

class DuplicateSkuException extends AppException {
  DuplicateSkuException(String sku) : super('SKU "$sku" is already used by another product.');
}

class CategoryInUseException extends AppException {
  const CategoryInUseException(super.message);
}
