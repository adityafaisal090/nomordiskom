import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';

/// Auth state management using ChangeNotifier (Provider pattern).
/// Manages user state, login/logout, and session persistence via Supabase.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  UserModel? _user;
  bool _isLoading = false;
  String? _errorMessage;

  // Global navigator key for force-logout/navigation from anywhere
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  AuthProvider(this._authService) {
    _listenToAuthState();
  }

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get errorMessage => _errorMessage;

  /// Listen to Supabase Auth State changes (signed out, token expired, etc.)
  void _listenToAuthState() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedOut || (event == AuthChangeEvent.tokenRefreshed && session == null)) {
        _user = null;
        notifyListeners();
        _navigateToLogin();
      }
    });
  }

  /// Check existing session on app startup.
  Future<bool> checkSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await _authService.checkSession();
      if (_user != null) {
        // Register FCM token for active session
        FcmService().registerCurrentToken();
      }
      return _user != null;
    } catch (_) {
      _user = null;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with credentials.
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.login(username, password);
      // Register device FCM token in Supabase profiles (safely, non-blocking)
      try {
        await FcmService().registerCurrentToken();
      } catch (fcmErr) {
        debugPrint('FCM token registration skipped/error: $fcmErr');
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout: clear session in Supabase and navigate to login.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _authService.logout();
    _user = null;
    _errorMessage = null;

    _isLoading = false;
    notifyListeners();

    _navigateToLogin();
  }

  /// Navigate to login screen, clearing the navigation stack
  void _navigateToLogin() {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
