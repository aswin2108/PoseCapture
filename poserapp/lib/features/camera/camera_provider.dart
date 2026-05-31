import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../pose/pose_category.dart';
import '../pose/pose_detector_service.dart';
import '../pose/pose_provider.dart';
import '../scene/scene_detector_service.dart';

final availableCamerasProvider = FutureProvider<List<CameraDescription>>((ref) {
  return availableCameras();
});

// ---------------------------------------------------------------------------
// Active camera index (0 = rear, 1 = front)
// ---------------------------------------------------------------------------

final activeCameraIndexProvider =
    NotifierProvider<_ActiveCameraIndexNotifier, int>(
  _ActiveCameraIndexNotifier.new,
);

class _ActiveCameraIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int value) => state = value;
}

// ---------------------------------------------------------------------------
// Last captured photo path
// ---------------------------------------------------------------------------

final lastPhotoProvider = NotifierProvider<_LastPhotoNotifier, String?>(
  _LastPhotoNotifier.new,
);

class _LastPhotoNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

// ---------------------------------------------------------------------------
// Camera controller + image stream → pose & scene detection
// ---------------------------------------------------------------------------

final cameraControllerProvider =
    AsyncNotifierProvider<CameraControllerNotifier, CameraController>(
  CameraControllerNotifier.new,
);

class CameraControllerNotifier extends AsyncNotifier<CameraController> {
  late PoseDetectorService _poseService;
  late SceneDetectorService _sceneService;
  CameraDescription? _cameraDesc;

  var _disposed = false;
  var _onFrameBusy = false;

  // Cleared when no pose is detected for 2 s — prevents a stale skeleton
  // persisting on screen after the user steps out of frame.
  Timer? _staleLandmarksTimer;

  // Cached once per session — gallery permission doesn't change mid-session.
  bool? _galAccessGranted;

  @override
  Future<CameraController> build() async {
    _disposed = false;
    _onFrameBusy = false;
    _staleLandmarksTimer?.cancel();
    _poseService = PoseDetectorService();
    _sceneService = SceneDetectorService();

    // Registered first → called THIRD on dispose (Riverpod LIFO order).
    ref.onDispose(_poseService.dispose);
    // Registered second → called SECOND on dispose.
    ref.onDispose(_sceneService.dispose);

    final cameras = await ref.watch(availableCamerasProvider.future);
    if (cameras.isEmpty) throw Exception('No cameras found');

    final index = ref.watch(activeCameraIndexProvider);
    final cameraDesc = cameras[index.clamp(0, cameras.length - 1)];
    _cameraDesc = cameraDesc;

    final controller = CameraController(
      cameraDesc,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller.initialize();

    await controller.startImageStream(_onFrame);

    // Registered third → called FIRST on dispose (LIFO): stream stopped and
    // controller freed before either ML service is closed.
    ref.onDispose(() {
      _staleLandmarksTimer?.cancel();
      _disposed = true;
      if (controller.value.isStreamingImages) {
        controller.stopImageStream().ignore();
      }
      controller.dispose();
    });

    return controller;
  }

  // -------------------------------------------------------------------------
  // Single image-stream callback used both in build() and after capture().
  // -------------------------------------------------------------------------

  Future<void> _onFrame(CameraImage image) async {
    if (_disposed) return;
    if (_onFrameBusy) return;
    _onFrameBusy = true;
    try {
      final desc = _cameraDesc;
      if (desc == null) return;

      // Pose detection — throttled internally to ~12fps.
      // null   = frame skipped (throttled/busy/format error) — do nothing.
      // empty  = frame actually ran, no person detected — start stale countdown.
      // filled = person detected.
      final landmarks = await _poseService.processFrame(image, desc);
      if (_disposed) return;
      if (landmarks == null) {
        // skipped — leave timer state unchanged
      } else if (landmarks.isEmpty) {
        // real detection: no person — start a 1.5 s countdown to clear skeleton
        _staleLandmarksTimer ??= Timer(const Duration(milliseconds: 1500), () {
          _staleLandmarksTimer = null;
          if (!_disposed) ref.read(detectedLandmarksProvider.notifier).set(null);
        });
      } else {
        // person detected — cancel any pending stale timer and push landmarks
        _staleLandmarksTimer?.cancel();
        _staleLandmarksTimer = null;
        ref.read(detectedLandmarksProvider.notifier).set(landmarks);
      }

      if (_disposed) return;

      // Scene detection — throttled internally to every 5 seconds; skip when
      // the user has manually selected a category.
      if (!ref.read(categoryManuallySetProvider)) {
        final category = await _sceneService.maybeDetect(image, desc);
        if (category != null && !_disposed) {
          ref.read(activePoseIndexProvider.notifier).set(0);
          ref.read(activeCategoryProvider.notifier).set(category);
        }
      }
    } finally {
      _onFrameBusy = false;
    }
  }

  // -------------------------------------------------------------------------

  // Called when the app is backgrounded — stops the ML stream without disposing
  // the controller so resume is fast.  The onDispose stopImageStream() call is
  // harmless if the stream is already stopped (.ignore() swallows the error).
  void pauseStream() {
    final ctrl = state.asData?.value;
    if (ctrl == null || !ctrl.value.isStreamingImages) return;
    ctrl.stopImageStream().ignore();
  }

  void flipCamera() {
    // Ignore if the camera is still initializing or mid-capture.
    if (state.isLoading) return;
    final ctrl = state.asData?.value;
    if (ctrl != null && ctrl.value.isTakingPicture) return;

    final cameras = ref.read(availableCamerasProvider).asData?.value;
    if (cameras == null || cameras.length < 2) return;

    ref.read(detectedLandmarksProvider.notifier).set(null);

    final current = ref.read(activeCameraIndexProvider);
    final nextIndex = (current + 1) % cameras.length;
    final nextCamera = cameras[nextIndex];

    // Reset manual override so scene detection takes over on the new camera.
    ref.read(categoryManuallySetProvider.notifier).set(false);

    // Front camera → selfie; rear → scene detection will pick on first frame.
    final defaultCategory = nextCamera.lensDirection == CameraLensDirection.front
        ? PoseCategory.selfie
        : PoseCategory.casual;
    ref.read(activeCategoryProvider.notifier).set(defaultCategory);
    ref.read(activePoseIndexProvider.notifier).set(0);

    ref.read(activeCameraIndexProvider.notifier).set(nextIndex);
  }

  Future<void> capture() async {
    final controller = state.asData?.value;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isTakingPicture) return;

    try {
      // Stop stream → take picture
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      if (_disposed) return;
      final file = await controller.takePicture();

      if (_galAccessGranted != true) {
        _galAccessGranted = await Gal.requestAccess();
      }
      if (_galAccessGranted == true) {
        await Gal.putImage(file.path);
        ref.read(lastPhotoProvider.notifier).set(file.path);
      }
    } catch (e) {
      debugPrint('capture: $e');
    } finally {
      // ALWAYS restart the image stream, even if takePicture or saving fails
      if (!_disposed && controller.value.isInitialized && !controller.value.isStreamingImages) {
        try {
          await controller.startImageStream(_onFrame);
        } catch (e) {
          debugPrint('Failed to restart camera stream: $e');
        }
      }
    }
  }
}
