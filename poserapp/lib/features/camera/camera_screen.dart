import 'dart:async';
import 'dart:io';
import 'dart:math' show pi, sqrt;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_drawing/path_drawing.dart';

import 'camera_provider.dart';
import 'focus_indicator.dart';
import 'zoom_control.dart';
import '../pose/category_selector.dart';
import '../pose/pose_carousel.dart';
import '../pose/pose_overlay_painter.dart';
import '../pose/pose_provider.dart';
import '../pose/pose_template.dart';
import '../settings/settings_provider.dart';
import '../settings/settings_sheet.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Stop the ML image stream while backgrounded — saves CPU and battery.
        // The controller is left alive so resume is fast (no full re-init).
        ref.read(cameraControllerProvider.notifier).pauseStream();
      case AppLifecycleState.resumed:
        // Full provider invalidation: disposes old controller then rebuilds,
        // which also handles the case where another app took the camera.
        ref.invalidate(cameraControllerProvider);
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraAsync = ref.watch(cameraControllerProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: cameraAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Camera error:\n$e',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (controller) => _CameraView(controller: controller),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CameraView extends ConsumerStatefulWidget {
  final CameraController controller;
  const _CameraView({required this.controller});

  @override
  ConsumerState<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<_CameraView>
    with TickerProviderStateMixin {
  // Flip animation
  late AnimationController _flipController;

  // Focus ring
  late AnimationController _focusController;
  late Animation<double> _focusScale;
  Offset? _focusPoint;
  bool _focusVisible = false;
  Timer? _focusTimer;

  // Raw pointer tracking for tap-to-focus (avoids gesture arena conflicts)
  int _activePointers = 0;
  Offset? _tapDownPos;
  DateTime? _tapDownTime;

  // Pinch-to-zoom
  double _baseZoom = 1.0;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  bool _showZoomLabel = false;
  Timer? _zoomLabelTimer;



  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _focusScale = Tween<double>(begin: 1.4, end: 1.0).animate(
      CurvedAnimation(parent: _focusController, curve: Curves.easeOut),
    );
    _initZoomLimits();
  }

  @override
  void didUpdateWidget(_CameraView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _focusTimer?.cancel();
      _zoomLabelTimer?.cancel();
      setState(() {
        _currentZoom = 1.0;
        _showZoomLabel = false;
        _focusPoint = null;
        _focusVisible = false;
      });
      _initZoomLimits();
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    _focusController.dispose();
    _focusTimer?.cancel();
    _zoomLabelTimer?.cancel();
    super.dispose();
  }

  Future<void> _initZoomLimits() async {
    try {
      final min = await widget.controller.getMinZoomLevel();
      final max = await widget.controller.getMaxZoomLevel();
      if (mounted) setState(() { _minZoom = min; _maxZoom = max; });
    } catch (_) {}
  }

  // --- Raw pointer events — detects tap without entering gesture arena ---

  void _onPointerDown(PointerDownEvent e) {
    _activePointers++;
    if (_activePointers == 1) {
      _tapDownPos = e.localPosition;
      _tapDownTime = DateTime.now();
    } else {
      // Multi-touch started — not a tap
      _tapDownPos = null;
      _tapDownTime = null;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    final downPos = _tapDownPos;
    final downTime = _tapDownTime;
    _tapDownPos = null;
    _tapDownTime = null;

    if (downPos == null || downTime == null) return;
    final elapsed = DateTime.now().difference(downTime).inMilliseconds;
    final moved = (e.localPosition - downPos).distance;
    if (elapsed < 250 && moved < 15) {
      _onFocusTap(e.localPosition);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    _tapDownPos = null;
    _tapDownTime = null;
  }

  Future<void> _onFocusTap(Offset localPos) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final normalized = Offset(
      localPos.dx / box.size.width,
      localPos.dy / box.size.height,
    );

    setState(() {
      _focusPoint = localPos;
      _focusVisible = true;
    });
    _focusController.forward(from: 0);

    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1700), () {
      if (mounted) setState(() => _focusVisible = false);
    });

    try {
      final c = widget.controller;
      if (c.value.focusPointSupported) await c.setFocusPoint(normalized);
      if (c.value.exposurePointSupported) await c.setExposurePoint(normalized);
    } catch (_) {}
  }

  // --- Scale gesture for pinch-to-zoom ---

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    if (details.pointerCount < 2) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return;
    setState(() {
      _currentZoom = newZoom;
      _showZoomLabel = true;
    });
    try {
      await widget.controller.setZoomLevel(_currentZoom);
    } catch (_) {}
    _zoomLabelTimer?.cancel();
    _zoomLabelTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showZoomLabel = false);
    });
  }


  // --- Camera flip ---

  void _onFlip() {
    ref.read(cameraControllerProvider.notifier).flipCamera();
    _flipController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final lastPhoto = ref.watch(lastPhotoProvider);



    return Stack(
      fit: StackFit.expand,
      children: [
        // Gesture layer: Listener for tap-to-focus, GestureDetector for pinch-zoom
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: _buildPreview(),
          ),
        ),
        // Pose skeleton overlay (reference ghost + user skeleton)
        ValueListenableBuilder<CameraValue>(
          valueListenable: widget.controller,
          builder: (context, value, child) {
            return RepaintBoundary(
              child: _PoseOverlay(
                deviceOrientation: value.deviceOrientation,
                previewSize: value.previewSize,
              ),
            );
          },
        ),
        // Focus ring
        if (_focusPoint != null)
          FocusRing(
            point: _focusPoint!,
            visible: _focusVisible,
            scaleAnimation: _focusScale,
          ),
        // Zoom badge floats above the bottom panel — fades in/out
        Positioned(
          bottom: 300,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _showZoomLabel ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: ZoomLevelBadge(zoomLevel: _currentZoom),
          ),
        ),
        // Top bar and bottom panel sit above gestures — they intercept their own taps
        _buildTopBar(),
        _buildBottomPanel(lastPhoto),
      ],
    );
  }

  Widget _buildPreview() {
    final previewSize = widget.controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();
    
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(widget.controller),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: AnimatedBuilder(
                  animation: _flipController,
                  builder: (_, child) => Transform.rotate(
                    angle: _flipController.value * 2 * pi,
                    child: child,
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                onPressed: _onFlip,
              ),
              IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () => showSettingsSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(String? lastPhoto) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const CategorySelector(),
              const SizedBox(height: 10),
              const PoseCarousel(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LastPhotoThumbnail(path: lastPhoto),
                    _CaptureButton(
                      onTap: () {
                        ref.read(cameraControllerProvider.notifier).capture();
                      },
                    ),
                    const SizedBox(width: 56), // Placeholder for balance
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Capture button with press animation
// ---------------------------------------------------------------------------

class _CaptureButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CaptureButton({required this.onTap});

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _controller.forward();
  void _onTapUp(_) {
    _controller.reverse();
    widget.onTap();
  }
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          padding: const EdgeInsets.all(5),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pose skeleton overlay — single Huawei-style neon guide skeleton
// ---------------------------------------------------------------------------

class _PoseOverlay extends ConsumerStatefulWidget {
  final DeviceOrientation deviceOrientation;
  final Size? previewSize;
  const _PoseOverlay({required this.deviceOrientation, this.previewSize});

  @override
  ConsumerState<_PoseOverlay> createState() => _PoseOverlayState();
}

class _PoseOverlayState extends ConsumerState<_PoseOverlay> with SingleTickerProviderStateMixin {
  Path? _baseSilhouettePath;
  PoseTemplate? _prevReferencePose;
  late AnimationController _drawController;
  Map<String, PoseLandmark>? _smoothedUserLandmarks;

  @override
  void initState() {
    super.initState();
    _drawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _drawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userLandmarks = ref.watch(detectedLandmarksProvider);
    final referencePose = ref.watch(activePoseProvider);
    final score = ref.watch(poseScoreProvider);
    final overlayOpacity = ref.watch(overlayOpacityProvider);
    final screenSize = MediaQuery.of(context).size;

    // Determine rotation angle from device orientation
    double angle = 0.0;
    if (widget.deviceOrientation == DeviceOrientation.landscapeLeft) {
      angle = pi / 2; // 90 degrees
    } else if (widget.deviceOrientation == DeviceOrientation.landscapeRight) {
      angle = -pi / 2; // -90 degrees
    } else if (widget.deviceOrientation == DeviceOrientation.portraitDown) {
      angle = pi; // 180 degrees
    }

    // 1. Update Base SVG Path if template changes
    if (referencePose != _prevReferencePose) {
      _prevReferencePose = referencePose;
      _baseSilhouettePath = null;
      _drawController.reset();

      if (referencePose != null && referencePose.svgPath.isNotEmpty) {
        try {
          _baseSilhouettePath = parseSvgPathData(referencePose.svgPath);
          _drawController.forward(from: 0.0);
        } catch (e) {
          debugPrint('Failed to parse SVG path: $e');
        }
      }
    }

    // 2. Smooth User Landmarks
    if (userLandmarks != null && userLandmarks.isNotEmpty) {
      if (_smoothedUserLandmarks == null || _smoothedUserLandmarks!.isEmpty) {
        _smoothedUserLandmarks = Map.from(userLandmarks);
      } else {
        final Map<String, PoseLandmark> next = {};
        for (final name in userLandmarks.keys) {
          final currentVal = userLandmarks[name]!;
          final prevVal = _smoothedUserLandmarks![name];
          if (prevVal != null) {
            const alpha = 0.15;
            next[name] = PoseLandmark(
              x: prevVal.x * (1.0 - alpha) + currentVal.x * alpha,
              y: prevVal.y * (1.0 - alpha) + currentVal.y * alpha,
            );
          } else {
            next[name] = currentVal;
          }
        }
        _smoothedUserLandmarks = next;
      }
    } else {
      _smoothedUserLandmarks = null;
    }

    // 3. Calculate Transform to Track User
    Matrix4 transform = Matrix4.identity();
    if (_baseSilhouettePath != null && referencePose != null) {
      // Parse viewBox e.g. "0 0 100 100"
      final vbParts = referencePose.svgViewBox.split(' ').map(double.tryParse).toList();
      double vbW = 100;
      double vbH = 100;
      if (vbParts.length == 4 && vbParts[2] != null && vbParts[3] != null) {
        vbW = vbParts[2]!;
        vbH = vbParts[3]!;
      }

      bool tracksUser = false;
      if (_smoothedUserLandmarks != null && widget.previewSize != null) {
        // Calculate BoxFit.cover mapping from preview to screen space
        final double previewW = widget.previewSize!.height; // swapped for portrait
        final double previewH = widget.previewSize!.width;
        final double screenRatio = screenSize.width / screenSize.height;
        final double previewRatio = previewW / previewH;

        double scaleX, scaleY, offsetX, offsetY;
        if (previewRatio > screenRatio) {
          scaleY = screenSize.height;
          scaleX = previewW * (screenSize.height / previewH);
          offsetX = -(scaleX - screenSize.width) / 2.0;
          offsetY = 0;
        } else {
          scaleX = screenSize.width;
          scaleY = previewH * (screenSize.width / previewW);
          offsetX = 0;
          offsetY = -(scaleY - screenSize.height) / 2.0;
        }

        Offset mapLm(PoseLandmark lm) {
          return Offset(lm.x * scaleX + offsetX, lm.y * scaleY + offsetY);
        }

        // ---------------------------------------------------------------
        // Tracking Logic: Try Torso first, then fall back to Shoulders,
        // then Hips, then Face (Ears/Nose).
        // ---------------------------------------------------------------
        final tLS = referencePose.landmarks['left_shoulder'];
        final tRS = referencePose.landmarks['right_shoulder'];
        final tLH = referencePose.landmarks['left_hip'];
        final tRH = referencePose.landmarks['right_hip'];
        final tLE = referencePose.landmarks['left_ear'];
        final tRE = referencePose.landmarks['right_ear'];
        final tNose = referencePose.landmarks['nose'];

        final uLS = _smoothedUserLandmarks!['left_shoulder'];
        final uRS = _smoothedUserLandmarks!['right_shoulder'];
        final uLH = _smoothedUserLandmarks!['left_hip'];
        final uRH = _smoothedUserLandmarks!['right_hip'];
        final uLE = _smoothedUserLandmarks!['left_ear'];
        final uRE = _smoothedUserLandmarks!['right_ear'];
        final uNose = _smoothedUserLandmarks!['nose'];

        final hasShoulders = tLS != null && tRS != null && uLS != null && uRS != null;
        final hasHips = tLH != null && tRH != null && uLH != null && uRH != null;
        final hasEars = tLE != null && tRE != null && uLE != null && uRE != null;
        final hasNose = tNose != null && uNose != null;

        double? tRefSize, uRefSize;
        double? tCenterX, tCenterY, uCenterX, uCenterY;

        if (hasEars && hasNose && (mapLm(uRE!).dx - mapLm(uLE!).dx).abs() > 20.0) {
          tRefSize = (tRE!.x - tLE!.x).abs() * vbW;
          tCenterX = tNose!.x * vbW;
          tCenterY = tNose.y * vbH;

          final mLE = mapLm(uLE!);
          final mRE = mapLm(uRE!);
          final mNose = mapLm(uNose!);
          uRefSize = (mRE.dx - mLE.dx).abs();
          uCenterX = mNose.dx;
          uCenterY = mNose.dy;
        } else if (hasNose && hasShoulders) {
          // Highly stable scale: diagonal of shoulder width and neck height.
          // Anchor: Nose (so the head matches perfectly like a filter).
          final tSCx = (tLS!.x + tRS!.x) / 2 * vbW;
          final tSCy = (tLS.y + tRS.y) / 2 * vbH;
          final tShW = (tRS.x - tLS.x).abs() * vbW;
          final tToN = (tSCy - tNose!.y * vbH).abs();
          tRefSize = sqrt(tShW * tShW + tToN * tToN);
          tCenterX = tNose.x * vbW;
          tCenterY = tNose.y * vbH;

          final mLS = mapLm(uLS!);
          final mRS = mapLm(uRS!);
          final mNose = mapLm(uNose!);
          final uSCx = (mLS.dx + mRS.dx) / 2;
          final uSCy = (mLS.dy + mRS.dy) / 2;
          final uShW = (mRS.dx - mLS.dx).abs();
          final uToN = (uSCy - mNose.dy).abs();
          uRefSize = sqrt(uShW * uShW + uToN * uToN);
          uCenterX = mNose.dx;
          uCenterY = mNose.dy;
        } else if (hasShoulders && hasHips) {
          final tSCx = (tLS!.x + tRS!.x) / 2 * vbW;
          final tSCy = (tLS.y + tRS.y) / 2 * vbH;
          final tHCx = (tLH!.x + tRH!.x) / 2 * vbW;
          final tHCy = (tLH.y + tRH.y) / 2 * vbH;
          final tShW = (tRS.x - tLS.x).abs() * vbW;
          final tToH = (tHCy - tSCy).abs();
          tRefSize = sqrt(tShW * tShW + tToH * tToH);
          tCenterX = (tSCx + tHCx) / 2;
          tCenterY = (tSCy + tHCy) / 2;

          final mLS = mapLm(uLS!);
          final mRS = mapLm(uRS!);
          final mLH = mapLm(uLH!);
          final mRH = mapLm(uRH!);

          final uSCx = (mLS.dx + mRS.dx) / 2;
          final uSCy = (mLS.dy + mRS.dy) / 2;
          final uHCx = (mLH.dx + mRH.dx) / 2;
          final uHCy = (mLH.dy + mRH.dy) / 2;
          final uShW = (mRS.dx - mLS.dx).abs();
          final uToH = (uHCy - uSCy).abs();
          uRefSize = sqrt(uShW * uShW + uToH * uToH);
          uCenterX = (uSCx + uHCx) / 2;
          uCenterY = (uSCy + uHCy) / 2;
        } else if (hasShoulders) {
          tRefSize = (tRS!.x - tLS!.x).abs() * vbW;
          tCenterX = (tLS.x + tRS.x) / 2 * vbW;
          tCenterY = (tLS.y + tRS.y) / 2 * vbH;

          final mLS = mapLm(uLS!);
          final mRS = mapLm(uRS!);
          uRefSize = (mRS.dx - mLS.dx).abs();
          uCenterX = (mLS.dx + mRS.dx) / 2;
          uCenterY = (mLS.dy + mRS.dy) / 2;
        } else if (hasHips) {
          tRefSize = (tRH!.x - tLH!.x).abs() * vbW;
          tCenterX = (tLH.x + tRH.x) / 2 * vbW;
          tCenterY = (tLH.y + tRH.y) / 2 * vbH;

          final mLH = mapLm(uLH!);
          final mRH = mapLm(uRH!);
          uRefSize = (mRH.dx - mLH.dx).abs();
          uCenterX = (mLH.dx + mRH.dx) / 2;
          uCenterY = (mLH.dy + mRH.dy) / 2;
        } else if (hasEars) {
          tRefSize = (tRE!.x - tLE!.x).abs() * vbW;
          tCenterX = (tLE.x + tRE.x) / 2 * vbW;
          tCenterY = (tLE.y + tRE.y) / 2 * vbH;

          final mLE = mapLm(uLE!);
          final mRE = mapLm(uRE!);
          uRefSize = (mRE.dx - mLE.dx).abs();
          uCenterX = (mLE.dx + mRE.dx) / 2;
          uCenterY = (mLE.dy + mRE.dy) / 2;
        } else if (hasNose) {
          tRefSize = vbH;
          tCenterX = tNose!.x * vbW;
          tCenterY = tNose.y * vbH;

          final mNose = mapLm(uNose!);
          uRefSize = screenSize.height * 0.85;
          uCenterX = mNose.dx;
          uCenterY = mNose.dy;
        }

        if (tRefSize != null && tRefSize > 0 &&
            uRefSize != null && uRefSize > 0) {
          final scale = uRefSize / tRefSize;

          transform = Matrix4.identity()
            ..translate(uCenterX!, uCenterY!)
            ..rotateZ(angle)
            ..scale(scale, scale)
            ..translate(-tCenterX!, -tCenterY!);
          tracksUser = true;
        }
      }

      // Default static position if no user detected
      if (!tracksUser) {
        // Fit within 85% of height and 85% of width to prevent cutoff
        final scaleY = screenSize.height * 0.85 / vbH;
        final scaleX = screenSize.width * 0.85 / vbW;
        final scale = (scaleX < scaleY) ? scaleX : scaleY;
        
        transform = Matrix4.identity()
          ..translate(screenSize.width / 2.0, screenSize.height / 2.0)
          ..rotateZ(angle)
          ..scale(scale)
          ..translate(-vbW / 2.0, -vbH / 2.0);
      }
    }

    Path? finalPath;
    if (_baseSilhouettePath != null) {
      finalPath = _baseSilhouettePath!.transform(transform.storage);
    }

    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _drawController,
          builder: (context, child) => CustomPaint(
            painter: PoseOverlayPainter(
              silhouettePath: finalPath,
              score: score,
              overlayOpacity: overlayOpacity,
              drawProgress: _drawController.value,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Last photo thumbnail
// ---------------------------------------------------------------------------

class _LastPhotoThumbnail extends StatelessWidget {
  final String? path;
  const _LastPhotoThumbnail({this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
        color: Colors.white12,
        image: path != null
            ? DecorationImage(
                image: FileImage(File(path!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: path == null
          ? const Icon(Icons.photo_outlined, color: Colors.white38, size: 22)
          : null,
    );
  }
}




