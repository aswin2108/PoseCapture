import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExisting();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkExisting();
  }

  Future<void> _checkExisting() async {
    final status = await Permission.camera.status;
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      context.go('/camera');
    } else if (status.isPermanentlyDenied) {
      setState(() => _permanentlyDenied = true);
    }
  }

  Future<void> _request() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      context.go('/camera');
    } else if (status.isPermanentlyDenied) {
      setState(() => _permanentlyDenied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(Icons.camera_alt_outlined, size: 80, color: AppTheme.primary)
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(
                    begin: const Offset(0.7, 0.7),
                    duration: 600.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 32),
              Text(
                'Camera Access',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.2, duration: 500.ms, curve: Curves.easeOut),
              const SizedBox(height: 12),
              Text(
                'PoseCam needs access to your camera to suggest and capture poses in real time.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppTheme.subtle),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 350.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.2, duration: 500.ms, curve: Curves.easeOut),
              const Spacer(),
              if (_permanentlyDenied) ...[
                Text(
                  'Camera access was denied. Please enable it in your device settings.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.subtle),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: openAppSettings,
                  child: const Text('Open Settings'),
                ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
              ] else
                ElevatedButton(
                  onPressed: _request,
                  child: const Text('Grant Camera Access'),
                )
                    .animate(delay: 500.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.3, duration: 400.ms, curve: Curves.easeOut),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
