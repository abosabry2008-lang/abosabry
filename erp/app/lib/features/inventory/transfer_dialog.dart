import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../models/product.dart';
import '../../models/warehouse.dart';
import '../shell/navigation.dart';
import 'stock_transfer_screen.dart';

/// Opens the multi-line stock transfer voucher. Returns `true` when a transfer
/// was posted.
Future<bool> showTransferDialog(
  BuildContext context, {
  Product? product,
  Location? fromLocation,
  String? warehouseId,
}) async {
  final result = await pushScreen<bool>(
    context,
    context.s.transferVoucher,
    StockTransferScreen(
      initialProduct: product,
      initialFromLocation: fromLocation,
      initialWarehouseId: warehouseId,
    ),
  );
  return result ?? false;
}
