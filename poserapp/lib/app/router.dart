import 'package:go_router/go_router.dart';
import '../features/permission/permission_screen.dart';
import '../features/camera/camera_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/permission',
  routes: [
    GoRoute(
      path: '/permission',
      builder: (context, state) => const PermissionScreen(),
    ),
    GoRoute(
      path: '/camera',
      builder: (context, state) => const CameraScreen(),
    ),
  ],
);
