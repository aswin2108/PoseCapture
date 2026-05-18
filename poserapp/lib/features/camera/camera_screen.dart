import 'dart:async';
import 'dart:io';
import 'dart:math' show pi;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_provider.dart';
import 'focus_indicator.dart';
import 'zoom_control.dart';
import '../pose/category_selector.dart';
import '../pose/pose_carousel.dart';
import '../pose/pose_overlay_painter.dart';
import '../pose/pose_provider.dart';
import '../pose/pose_silhouette.dart';
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

  // Auto-capture countdown
  static const _kStartThreshold = 0.82;
  static const _kCancelThreshold = 0.72;
  int? _countdownValue;
  Timer? _countdownTimer;

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
      _cancelCountdown();
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
    _countdownTimer?.cancel();
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

  // --- Auto-capture countdown ---

  void _startCountdown() {
    if (_countdownValue != null) return;
    final duration = ref.read(countdownDurationProvider);
    setState(() => _countdownValue = duration);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      // _countdownValue can be null if _cancelCountdown() ran between the
      // timer firing and this callback executing — Dart's event queue does
      // not remove already-queued callbacks on cancel(). Guard here to
      // prevent a phantom capture after the countdown was cancelled.
      final current = _countdownValue;
      if (current == null) { timer.cancel(); return; }
      final next = current - 1;
      if (next <= 0) {
        timer.cancel();
        _countdownTimer = null;
        setState(() => _countdownValue = null);
        ref.read(cameraControllerProvider.notifier).capture();
      } else {
        setState(() => _countdownValue = next);
      }
    });
  }

  void _cancelCountdown() {
    if (_countdownValue == null) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) setState(() => _countdownValue = null);
  }

  // --- Camera flip ---

  void _onFlip() {
    ref.read(cameraControllerProvider.notifier).flipCamera();
    _flipController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final lastPhoto = ref.watch(lastPhotoProvider);

    // Cancel countdown when the user disables auto-capture mid-flight.
    ref.listen(autoCaptureEnabledProvider, (_, enabled) {
      if (!enabled) _cancelCountdown();
    });

    // Drive the countdown based on pose score with hysteresis to avoid
    // flickering near the threshold.
    ref.listen(poseScoreProvider, (_, score) {
      if (!ref.read(autoCaptureEnabledProvider)) return;
      if (score >= _kStartThreshold) {
        _startCountdown();
      } else if (score < _kCancelThreshold) {
        _cancelCountdown();
      }
    });

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
        RepaintBoundary(child: const _PoseOverlay()),
        // Focus ring
        if (_focusPoint != null)
          FocusRing(
            point: _focusPoint!,
            visible: _focusVisible,
            scaleAnimation: _focusScale,
          ),
        // Auto-capture countdown number
        if (_countdownValue != null)
          _CountdownOverlay(value: _countdownValue!),
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
                        _cancelCountdown();
                        ref.read(cameraControllerProvider.notifier).capture();
                      },
                    ),
                    const _AutoCaptureToggle(),
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
  const _PoseOverlay();

  @override
  ConsumerState<_PoseOverlay> createState() => _PoseOverlayState();
}

class _PoseOverlayState extends ConsumerState<_PoseOverlay> {
  Path? _cachedNormalizedSilhouette;
  PoseTemplate? _prevReferencePose;
  
  // Smoothing state to prevent jitter
  double? _smoothScale;
  double? _smoothTx;
  double? _smoothTy;
  Matrix4? _transform;
  Map<String, PoseLandmark>? _prevUserLandmarks;

  @override
  Widget build(BuildContext context) {
    final userLandmarks = ref.watch(detectedLandmarksProvider);
    final referencePose = ref.watch(activePoseProvider);
    final score = ref.watch(poseScoreProvider);
    final overlayOpacity = ref.watch(overlayOpacityProvider);

    if (!identical(referencePose, _prevReferencePose)) {
      _prevReferencePose = referencePose;
      _cachedNormalizedSilhouette = referencePose != null
          ? PoseSilhouette.buildNormalizedSilhouette(referencePose.landmarks)
          : null;
    }

    if (!identical(userLandmarks, _prevUserLandmarks) ||
        !identical(referencePose, _prevReferencePose)) {
      _prevUserLandmarks = userLandmarks;
      
      final rawMatrix = referencePose != null
          ? _getAdaptationMatrix(referencePose.landmarks, userLandmarks)
          : null;
          
      if (rawMatrix != null) {
        // Extract scale and translation from the raw matrix
        final s = rawMatrix.storage[0];
        final tx = rawMatrix.storage[12];
        final ty = rawMatrix.storage[13];

        // Apply low-pass filter (Exponential Moving Average)
        if (_smoothScale == null) {
          // First frame lock
          _smoothScale = s;
          _smoothTx = tx;
          _smoothTy = ty;
        } else {
          // Slow glide towards target (0.1 means 90% stays put, 10% moves to target)
          // This makes the outline "stay still where it's supposed to" and absorb jitter
          _smoothScale = _smoothScale! * 0.90 + s * 0.10;
          _smoothTx = _smoothTx! * 0.90 + tx * 0.10;
          _smoothTy = _smoothTy! * 0.90 + ty * 0.10;
        }

        _transform = Matrix4.identity()
          ..translate(_smoothTx!, _smoothTy!)
          ..scale(_smoothScale!, _smoothScale!);
      } else {
        _transform = null;
        _smoothScale = null;
      }
    }

    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: PoseOverlayPainter(
            silhouettePath: _cachedNormalizedSilhouette,
            transform: _transform,
            score: score,
            overlayOpacity: overlayOpacity,
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

// ---------------------------------------------------------------------------
// Auto-capture toggle button
// ---------------------------------------------------------------------------

class _AutoCaptureToggle extends ConsumerWidget {
  const _AutoCaptureToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autoCaptureEnabledProvider);
    return GestureDetector(
      onTap: () => ref.read(autoCaptureEnabledProvider.notifier).toggle(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: enabled ? Colors.transparent : Colors.white38,
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.timer_outlined,
          color: enabled ? Colors.black : Colors.white70,
          size: 24,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown overlay — shown centre-screen during auto-capture
// ---------------------------------------------------------------------------

class _CountdownOverlay extends StatelessWidget {
  final int value;
  const _CountdownOverlay({required this.value});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: Tween<double>(begin: 1.5, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Text(
            '$value',
            key: ValueKey(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 120,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black54, blurRadius: 24)],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Adapts reference pose landmarks to match the user's detected body scale and
// position. Runs in build() rather than paint() to avoid per-frame allocation.
// Primary anchor: hip centre + torso height.
// Fallback: shoulder centre + shoulder width (upper-body-only detection).
// Returns null when insufficient landmarks are available.
// ---------------------------------------------------------------------------

Matrix4? _getAdaptationMatrix(
  Map<String, PoseLandmark> reference,
  Map<String, PoseLandmark>? user,
) {
  if (user == null || user.isEmpty) return null;

  final uLS = user['left_shoulder'], uRS = user['right_shoulder'];
  final uLH = user['left_hip'], uRH = user['right_hip'];
  final rLS = reference['left_shoulder'], rRS = reference['right_shoulder'];
  final rLH = reference['left_hip'], rRH = reference['right_hip'];

  if (uLS != null && uRS != null && uLH != null && uRH != null &&
      rLS != null && rRS != null && rLH != null && rRH != null) {
    final uHip = Offset((uLH.x + uRH.x) / 2, (uLH.y + uRH.y) / 2);
    final uSh = Offset((uLS.x + uRS.x) / 2, (uLS.y + uRS.y) / 2);
    final rHip = Offset((rLH.x + rRH.x) / 2, (rLH.y + rRH.y) / 2);
    final rSh = Offset((rLS.x + rRS.x) / 2, (rLS.y + rRS.y) / 2);
    final uTorso = (uSh - uHip).distance;
    final rTorso = (rSh - rHip).distance;

    if (uTorso > 0.03 && rTorso > 0.001) {
      final s = uTorso / rTorso;
      // We only need the translation to align the user's hip with the reference hip's scaled position
      final tx = uHip.dx - (rHip.dx * s);
      final ty = uHip.dy - (rHip.dy * s);
      return Matrix4.identity()
        ..translate(tx, ty)
        ..scale(s, s);
    }
  }

  if (uLS != null && uRS != null && rLS != null && rRS != null) {
    final uCx = (uLS.x + uRS.x) / 2, uCy = (uLS.y + uRS.y) / 2;
    final rCx = (rLS.x + rRS.x) / 2, rCy = (rLS.y + rRS.y) / 2;
    final uW = (Offset(uLS.x, uLS.y) - Offset(uRS.x, uRS.y)).distance;
    final rW = (Offset(rLS.x, rLS.y) - Offset(rRS.x, rRS.y)).distance;

    if (uW > 0.03 && rW > 0.001) {
      final s = uW / rW;
      final tx = uCx - (rCx * s);
      final ty = uCy - (rCy * s);
      return Matrix4.identity()
        ..translate(tx, ty)
        ..scale(s, s);
    }
  }

  return null;
}
