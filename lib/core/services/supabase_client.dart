import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

class SupabaseAuthHelper {
  final SupabaseClient _client;

  SupabaseAuthHelper(this._client);

  /// Ensures the client has an active anonymous session without overwriting an existing one.
  Future<String> ensureAnonymousAuth() async {
    final currentSession = _client.auth.currentSession;
    if (currentSession != null && _client.auth.currentUser != null) {
      return _client.auth.currentUser!.id;
    }

    final response = await _client.auth.signInAnonymously();
    if (response.user == null) {
      throw Exception('Failed to obtain anonymous authentication session');
    }
    return response.user!.id;
  }

  String? get currentUid => _client.auth.currentUser?.id;
}

final supabaseAuthProvider = Provider<SupabaseAuthHelper>((ref) {
  return SupabaseAuthHelper(ref.watch(supabaseClientProvider));
});
