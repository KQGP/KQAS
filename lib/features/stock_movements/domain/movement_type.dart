enum StockDirection { inbound, outbound }

/// Movement types that change PHYSICAL stock. Reservation types
/// (loading reservation / release) arrive in Phase 7 with the reservation engine.
enum MovementType {
  openingBalance('Opening balance', StockDirection.inbound),
  purchase('Purchase (incoming)', StockDirection.inbound),
  sale('Sale (outgoing)', StockDirection.outbound),
  supplierReturn('Supplier return', StockDirection.outbound),
  customerReturn('Customer return', StockDirection.inbound),
  transferOut('Transfer out', StockDirection.outbound),
  transferIn('Transfer in', StockDirection.inbound),
  manualIncrease('Manual increase', StockDirection.inbound, reasonRequired: true),
  manualDecrease('Manual decrease', StockDirection.outbound, reasonRequired: true),
  damaged('Damaged goods', StockDirection.outbound, reasonRequired: true),
  lost('Lost goods', StockDirection.outbound, reasonRequired: true),
  expired('Expired goods', StockDirection.outbound, reasonRequired: true),
  correction('Stock correction', null, reasonRequired: true),
  deliveryConfirmation('Delivery confirmation', StockDirection.outbound),
  unloadingReturn('Unloading / returned goods', StockDirection.inbound),
  reversal('Reversal (compensating)', null, reasonRequired: true);

  const MovementType(this.label, this.fixedDirection, {this.reasonRequired = false});

  final String label;

  /// null => the caller must supply the direction (corrections, reversals).
  final StockDirection? fixedDirection;
  final bool reasonRequired;

  static MovementType fromName(String name) =>
      values.firstWhere((t) => t.name == name, orElse: () => MovementType.correction);
}
