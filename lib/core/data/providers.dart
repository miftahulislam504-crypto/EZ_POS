import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../models/app_user.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Overridden in main'));

/// Emits auth events (sign in, sign out, token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

/// Only changes when a different user signs in or out, so token refreshes do not rebuild the app.
final userIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

/// The signed-in user's membership, business, branch and permissions. Null means: needs business setup.
final appUserProvider = FutureProvider<AppUser?>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return null;
  final client = ref.watch(supabaseProvider);

  final member = await client.from('business_members').select('*, businesses(*)').eq('user_id', userId).maybeSingle();
  if (member == null) return null;
  if (member['is_active'] != true) throw const AccountDisabledException();

  final business = Business.fromJson(Map<String, dynamic>.from(member['businesses'] as Map));
  final role = member['role'] as String;

  var permissions = <String>{};
  if (role == 'owner') {
    permissions = Perm.all.toSet();
  } else {
    final rows = await client.from('role_permissions').select('permission').eq('role', role);
    permissions = {for (final r in rows) r['permission'] as String};
  }

  final branches = await client
      .from('branches')
      .select('id, name, is_default')
      .eq('business_id', business.id)
      .eq('is_active', true);
  Map<String, dynamic>? branch;
  for (final b in branches) {
    if (b['id'] == member['branch_id']) branch = Map<String, dynamic>.from(b);
  }
  branch ??= branches.isEmpty
      ? null
      : Map<String, dynamic>.from(branches.firstWhere((b) => b['is_default'] == true, orElse: () => branches.first));

  return AppUser(
    userId: userId,
    memberId: member['id'] as String,
    fullName: member['full_name'] as String,
    email: member['email'] as String?,
    role: role,
    business: business,
    branchId: (branch?['id'] as String?) ?? '',
    branchName: (branch?['name'] as String?) ?? 'Main Branch',
    permissions: permissions,
  );
});

AppUser? _lastKnownUser;

/// Convenience: the current user. Keeps the last known user for the single frame between sign-out and redirect.
final currentUserProvider = Provider<AppUser>((ref) {
  final u = ref.watch(appUserProvider).valueOrNull;
  if (u != null) _lastKnownUser = u;
  final user = u ?? _lastKnownUser;
  if (user == null) throw StateError('No signed-in user');
  return user;
});

class ThemeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return switch (saved) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPrefsProvider).setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
