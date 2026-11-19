import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDisabledException implements Exception {
  const AccountDisabledException();
}

/// Turns any error into one short sentence a shop owner can act on.
String friendlyError(Object e) {
  if (e is AccountDisabledException) {
    return 'This account has been deactivated. Please contact the business owner.';
  }
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('products_sku_uq')) return 'This SKU is already used by another product.';
    if (m.contains('products_barcode_uq')) return 'This barcode is already assigned to another product.';
    if (m.contains('customers_phone_uq')) return 'A customer with this phone number already exists.';
    if (m.contains('categories_name_uq')) return 'A category with this name already exists.';
    if (m.contains('row-level security')) return 'You do not have permission to do this.';
    if (m.contains('violates foreign key')) return 'This record is in use and cannot be removed.';
    return m;
  }
  if (e is AuthException) {
    final m = e.message;
    if (m.toLowerCase().contains('invalid login')) return 'Incorrect email or password.';
    return m;
  }
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] != null) return d['error'].toString();
    return e.reasonPhrase ?? 'The request failed. Please try again.';
  }
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
    return 'No internet connection. Check your network and try again.';
  }
  return s.replaceFirst('Exception: ', '');
}
