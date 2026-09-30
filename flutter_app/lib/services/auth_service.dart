import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

/// Handles authentication operations using Supabase Auth (Cloud 24/7).
class AuthService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Helper to convert username input to email format for Supabase Auth
  String _normalizeEmail(String input) {
    final trimmed = input.trim().toLowerCase();
    if (trimmed.contains('@')) {
      return trimmed;
    }
    return '$trimmed@siagenda.local';
  }

  /// Login with username (or email) and password.
  /// Returns UserModel on success, throws on failure.
  Future<UserModel> login(String usernameInput, String password) async {
    final email = _normalizeEmail(usernameInput);

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('User tidak ditemukan.');
      }

      return UserModel.fromSupabaseUser(user);
    } on AuthException catch (e) {
      if (e.message.contains('Invalid login credentials')) {
        throw Exception('Username atau password salah.');
      }
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Gagal terhubung ke Supabase. Silakan periksa koneksi internet Anda.');
    }
  }

  /// Check existing active Supabase session.
  /// Returns UserModel if session is valid, null otherwise.
  Future<UserModel?> checkSession() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return null;
    }
    return UserModel.fromSupabaseUser(user);
  }

  /// Logout current user from Supabase.
  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Ignore errors on signout
    }
  }
}
