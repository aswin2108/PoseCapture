import 'package:flutter/material.dart';

class PoseOverlayPainter extends CustomPainter {
  final Path? silhouettePath;
  final double score;
  final double overlayOpacity;
  final double drawProgress;

  const PoseOverlayPainter({
    this.silhouettePath,
    this.score = 0.0,
    this.overlayOpacity = 1.0,
    this.drawProgress = 1.0,
  });

  static const _kGreen = Color(0xFF69F0AE);

  @override
  void paint(Canvas canvas, Size size) {
    if (silhouettePath == null) return;

    final op = overlayOpacity.clamp(0.0, 1.0);
    if (op == 0.0 || drawProgress == 0.0) return;

    Path finalPath = silhouettePath!;

    final animatedPath = Path();
    for (final metric in finalPath.computeMetrics()) {
      final extractLength = metric.length * drawProgress;
      animatedPath.addPath(metric.extractPath(0.0, extractLength), Offset.zero);
    }
    finalPath = animatedPath;

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
      score != old.score ||
      overlayOpacity != old.overlayOpacity ||
      drawProgress != old.drawProgress;
}

