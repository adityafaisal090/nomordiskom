import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'providers/auth_provider.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/form_agenda_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase Cloud 24/7 Service
  await Supabase.initialize(
    url: 'https://afqsalcedeloenwcngji.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmcXNhbGNlZGVsb2Vud2NuZ2ppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU2ODIyOTAsImV4cCI6MjEwMTI1ODI5MH0.SV3gG1PwtWkWzGCIX-K6xWMxp9RiegJSqj5P49phwC4',
  );

  // 2. Initialize Firebase & FCM Notification Engine
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FcmService().initialize();
  } catch (e) {
    debugPrint('Firebase/FCM init skipped or errored: $e');
  }

  runApp(const MonaApp());
}

class MonaApp extends StatelessWidget {
  const MonaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return ChangeNotifierProvider(
      create: (_) => AuthProvider(authService),
      child: MaterialApp(
        title: 'MONA',
        debugShowCheckedModeBanner: false,
        navigatorKey: AuthProvider.navigatorKey,
        theme: AppTheme.lightTheme,
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/login': (_) => const LoginScreen(),
          '/home': (_) => const HomeScreen(),
          '/form-agenda': (_) => const FormAgendaScreen(),
        },
      ),
    );
  }
}
