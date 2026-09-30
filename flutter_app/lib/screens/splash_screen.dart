import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version_model.dart';
import '../providers/auth_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';

/// Splash screen shown on app startup.
/// Checks for app auto-update, then checks existing session.
/// Routes to HomeScreen if valid, LoginScreen if not.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  final _updateService = UpdateService();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSessionAndUpdates();
    });
  }

  Future<void> _checkSessionAndUpdates() async {
    final authProvider = context.read<AuthProvider>();

    // Parallel execution of session check, update check, and minimum splash delay
    final results = await Future.wait([
      authProvider.checkSession(),
      _updateService.checkLatestVersion(),
      _updateService.getCurrentPackageInfo(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    final isLoggedIn = results[0] as bool;
    final latestVersion = results[1] as AppVersionModel?;
    final packageInfo = results[2] as PackageInfo;

    if (!mounted) return;

    // Check if an update is available on server
    if (latestVersion != null) {
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 1;
      if (latestVersion.hasUpdate(currentCode)) {
        await showUpdateDialog(
          context,
          version: latestVersion,
          currentVersionCode: currentCode,
        );

        if (latestVersion.isMandatory(currentCode)) {
          // If mandatory and user dismissed or still not updated, stay on splash
          return;
        }
      }
    }

    if (!mounted) return;

    if (isLoggedIn) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceAlt,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // MONA App icon / branding
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/app_logo.jpeg',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Text(
                      'M',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'MONA',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Monitoring Nomor Agenda',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dinas Komunikasi dan Informatika',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
