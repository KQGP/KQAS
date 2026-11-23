import '../../../database/tables/common.dart';

enum InvoiceType { incoming, outgoing }

extension InvoiceTypeX on InvoiceType {
  String get wire => name; // incoming | outgoing
  static InvoiceType fromWire(String v) =>
      InvoiceType.values.firstWhere((e) => e.name == v, orElse: () => InvoiceType.incoming);
}

enum InvoiceStatus {
  draft,
  pending,
  partiallyReceived,
  received,
  partiallyDispatched,
  dispatched,
  cancelled,
  reversed,
}

extension InvoiceStatusX on InvoiceStatus {
  String get wire => switch (this) {
        InvoiceStatus.partiallyReceived => 'partiallyReceived',
        InvoiceStatus.partiallyDispatched => 'partiallyDispatched',
        _ => name,
      };
  static InvoiceStatus fromWire(String v) => InvoiceStatus.values.firstWhere(
        (e) => e.wire == v,
        orElse: () => InvoiceStatus.draft,
      );
}

class InvoiceItemInput {
  const InvoiceItemInput({
    this.productId,
    this.description,
    this.sku,
    this.barcode,
    required this.expectedQuantity,
    this.unitPriceMinor,
  });
  final String? productId;
  final String? description;
  final String? sku;
  final String? barcode;
  final int expectedQuantity; // scaled
  final int? unitPriceMinor;
}

class InvoiceInput {
  const InvoiceInput({
    this.id,
    required this.invoiceNumber,
    required this.type,
    this.supplierId,
    this.customerId,
    this.invoiceDate,
    this.notes,
    this.items = const [],
    this.taxMinor = 0,
    this.discountMinor = 0,
    this.sourcePdfPath,
  });
  final String? id;
  final String invoiceNumber;
  final InvoiceType type;
  final String? supplierId;
  final String? customerId;
  final DateTime? invoiceDate;
  final String? notes;
  final List<InvoiceItemInput> items;
  final int taxMinor;
  final int discountMinor;
  final String? sourcePdfPath;
}
