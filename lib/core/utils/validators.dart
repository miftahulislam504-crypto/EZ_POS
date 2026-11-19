class Validators {
  Validators._();

  static String? Function(String?) required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? optionalEmail(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    return v.length < 8 ? 'Use at least 8 characters' : null;
  }

  static String? optionalPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final digits = v.replaceAll(RegExp(r'[\s\-+()]'), '');
    return RegExp(r'^\d{7,15}$').hasMatch(digits) ? null : 'Enter a valid phone number';
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    return optionalPhone(v);
  }

  static String? Function(String?) positive(String label) => (v) {
        final n = double.tryParse((v ?? '').replaceAll(',', '').trim());
        if (n == null || n <= 0) return '$label must be greater than zero';
        return null;
      };

  static String? Function(String?) nonNegative(String label) => (v) {
        if (v == null || v.trim().isEmpty) return null;
        final n = double.tryParse(v.replaceAll(',', '').trim());
        if (n == null || n < 0) return '$label cannot be negative';
        return null;
      };
}
