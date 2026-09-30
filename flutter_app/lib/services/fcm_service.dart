import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) {
    print("Handling background message: ${message.messageId}");
  }
}

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  Function(String agendaId)? onNotificationTap;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'mona_default_channel',
    'Notifikasi MONA',
    description: 'Saluran resmi notifikasi nomor agenda MONA',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize FCM, local heads-up notifications, request permissions, and register token
  Future<void> initialize({Function(String agendaId)? onNotificationTapHandler}) async {
    onNotificationTap = onNotificationTapHandler;

    if (kIsWeb) {
      if (kDebugMode) {
        print('FCM: Web platform detected, push notification registration skipped (mobile only).');
      }
      return;
    }

    try {
      // 1. Setup local notification channel for Heads-Up popup in Foreground
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            onNotificationTap?.call(payload);
          }
        },
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // 2. Set background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 3. Request notification permissions (Android 13+ & iOS)
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        if (kDebugMode) {
          print('User granted notification permission');
        }

        // Get initial token and register if user is already logged in
        final token = await _fcm.getToken();
        if (token != null) {
          await registerFcmToken(token);
        }

        // Listen for token refreshes
        _fcm.onTokenRefresh.listen((newToken) async {
          await registerFcmToken(newToken);
        });

        // Setup message listeners
        _setupMessageListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCM Initialization error: $e');
      }
    }
  }

  /// Register current device FCM token with Supabase (call after login / session restore)
  Future<void> registerCurrentToken() async {
    if (kIsWeb) return;

    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await registerFcmToken(token);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting/registering current FCM token: $e');
      }
    }
  }

  /// Call Supabase RPC `update_fcm_token` to persist token in profiles
  Future<void> registerFcmToken(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.rpc('update_fcm_token', params: {
          'p_token': token,
        });
        if (kDebugMode) {
          print('Successfully updated FCM token in Supabase for user ${user.id}: $token');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to register FCM token with Supabase: $e');
      }
    }
  }

  /// Setup foreground, background-tapped, and terminated notification listeners
  void _setupMessageListeners() {
    // 1. Foreground message handler: display Heads-Up popup & In-App SnackBar
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('Foreground notification received: ${message.notification?.title}');
      }
      _showLocalHeadsUpNotification(message);
      _showInAppNotification(message);
    });

    // 2. Background notification tap handler
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final agendaId = message.data['agenda_id']?.toString();
      if (agendaId != null && agendaId.isNotEmpty) {
        onNotificationTap?.call(agendaId);
      }
    });

    // 3. Terminated launch notification handler
    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        final agendaId = message.data['agenda_id']?.toString();
        if (agendaId != null && agendaId.isNotEmpty) {
          onNotificationTap?.call(agendaId);
        }
      }
    });
  }

  /// Display a native Heads-Up status bar notification when message arrives in Foreground
  void _showLocalHeadsUpNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? 'Notifikasi MONA';
    final body = notification?.body ?? message.data['body'] ?? '';
    final agendaId = message.data['agenda_id']?.toString() ?? '';

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
          color: const Color(0xFF2F6FED),
          playSound: true,
          enableVibration: true,
        ),
      ),
      payload: agendaId,
    );
  }

  /// Display an in-app SnackBar when notification arrives while app is in foreground
  void _showInAppNotification(RemoteMessage message) {
    final title = message.notification?.title ?? 'Notifikasi Baru';
    final body = message.notification?.body ?? '';
    final context = AuthProvider.navigatorKey.currentContext;

    if (context != null && (title.isNotEmpty || body.isNotEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
          ),
          elevation: 6,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_logo.jpeg',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primary, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}

