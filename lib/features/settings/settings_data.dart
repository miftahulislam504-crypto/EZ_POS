import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/utils/json.dart';

class Member {
  const Member({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    required this.isActive,
    this.phone,
    this.email,
    this.employeeCode,
    this.joinedOn,
  });

  final String id;
  final String userId;
  final String name;
  final String role;
  final bool isActive;
  final String? phone;
  final String? email;
  final String? employeeCode;
  final DateTime? joinedOn;

  bool get isOwner => role == 'owner';

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['full_name'] as String,
        role: j['role'] as String,
        isActive: j['is_active'] == true,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        employeeCode: j['employee_code'] as String?,
        joinedOn: parseDate(j['joined_on']),
      );
}

String roleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'manager' => 'Manager',
      'cashier' => 'Cashier',
      'storekeeper' => 'Storekeeper',
      _ => role,
    };

class SettingsRepository {
  SettingsRepository(this._client, this._businessId);

  final SupabaseClient _client;
  final String _businessId;

  Future<void> updateBusiness(Map<String, dynamic> data) => _client.from('businesses').update(data).eq('id', _businessId);

  /// Merges [patch] into the stored settings document.
  Future<void> saveSettings(Business current, Map<String, dynamic> patch) {
    final merged = {...current.settings, ...patch};
    return _client.from('businesses').update({'settings': merged}).eq('id', _businessId);
  }

  Future<String> uploadLogo(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final path = '$_businessId/logo-${const Uuid().v4()}.$ext';
    await _client.storage.from('business-assets').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}', upsert: false));
    return _client.storage.from('business-assets').getPublicUrl(path);
  }

  Future<List<Member>> members() async {
    final rows = await _client.from('business_members').select().order('created_at');
    return [for (final r in rows) Member.fromJson(r)];
  }

  Future<void> updateMember(String id, Map<String, dynamic> data) => _client.from('business_members').update(data).eq('id', id);

  Future<void> createStaff({required String email, required String password, required String fullName, required String role, String? phone}) async {
    await _client.functions.invoke('create-staff', body: {
      'action': 'create',
      'email': email,
      'password': password,
      'full_name': fullName,
      'role': role,
      'phone': phone,
    });
  }

  Future<void> resetPassword(String memberId, String password) async {
    await _client.functions.invoke('create-staff', body: {'action': 'reset_password', 'member_id': memberId, 'password': password});
  }

  Future<Set<String>> permissionsFor(String role) async {
    final rows = await _client.from('role_permissions').select('permission').eq('role', role);
    return {for (final r in rows) r['permission'] as String};
  }

  Future<void> setPermission(String role, String permission, bool enabled) async {
    if (enabled) {
      await _client.from('role_permissions').upsert({'business_id': _businessId, 'role': role, 'permission': permission}, ignoreDuplicates: true);
    } else {
      await _client.from('role_permissions').delete().eq('role', role).eq('permission', permission);
    }
  }
}

final settingsRepoProvider = Provider<SettingsRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  return SettingsRepository(ref.watch(supabaseProvider), user.businessId);
});

final membersProvider = FutureProvider.autoDispose<List<Member>>((ref) => ref.watch(settingsRepoProvider).members());

final rolePermissionsProvider = FutureProvider.autoDispose.family<Set<String>, String>((ref, role) {
  return ref.watch(settingsRepoProvider).permissionsFor(role);
});
