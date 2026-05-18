import 'package:flutter/material.dart';

class PoseOverlayPainter extends CustomPainter {
  final Path? silhouettePath;
  final Matrix4? transform;
  final double score;
  final double overlayOpacity;

  const PoseOverlayPainter({
    this.silhouettePath,
    this.transform,
    this.score = 0.0,
    this.overlayOpacity = 1.0,
  });

  static const _kCyan = Color(0xFF00E5FF);
  static const _kGreen = Color(0xFF69F0AE);

  @override
  void paint(Canvas canvas, Size size) {
    if (silhouettePath == null || transform == null) return;

    final op = overlayOpacity.clamp(0.0, 1.0);
    if (op == 0.0) return;

    // Apply the adaptation transform (normalized space -> user's screen space)
    final userPath = silhouettePath!.transform(transform!.storage);

    // Scale to the actual canvas pixel size (since coordinates were 0..1)
    final screenScaleMatrix = Matrix4.identity()
      ..scale(size.width, size.height);
    final finalPath = userPath.transform(screenScaleMatrix.storage);

    // Determine whole-silhouette color based on the score
    // Huawei UI: transitions from white to a vibrant match color
    final baseColor = Color.lerp(Colors.white, _kGreen, score)!;

    // 1. Soft Outer Glow
    canvas.drawPath(
      finalPath,
      Paint()
        ..color = baseColor.withValues(alpha: op * 0.35)
        ..strokeWidth = 14.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0),
    );

    // 2. Thick Core Line (The "White Curvy Line")
    canvas.drawPath(
      finalPath,
      Paint()
        ..color = baseColor.withValues(alpha: op * 0.95)
        ..strokeWidth = 3.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(PoseOverlayPainter old) =>
      silhouettePath != old.silhouettePath ||
      transform != old.transform ||
      score != old.score ||
      overlayOpacity != old.overlayOpacity;
}
