import 'dart:math' show sqrt, atan2;
import 'package:flutter/material.dart';
import 'pose_template.dart';

class PoseSilhouette {
  /// Builds a continuous outline Path for a given pose template in its native normalized space (0..1).
  /// Uses tapered polygons for limbs and torso to create an anatomical, non-bloated contour.
  static Path buildNormalizedSilhouette(Map<String, PoseLandmark> lms) {
    Offset pt(String name) {
      final lm = lms[name];
      return lm != null ? Offset(lm.x, lm.y) : Offset.zero;
    }

    final n = pt('nose');
    final ls = pt('left_shoulder');
    final rs = pt('right_shoulder');
    final le = pt('left_elbow');
    final re = pt('right_elbow');
    final lw = pt('left_wrist');
    final rw = pt('right_wrist');
    final lh = pt('left_hip');
    final rh = pt('right_hip');
    final lk = pt('left_knee');
    final rk = pt('right_knee');
    final la = pt('left_ankle');
    final ra = pt('right_ankle');

    double baseUnit = (ls - rs).distance;
    if (baseUnit < 0.01) baseUnit = 0.2;

    // Center of mass for inflation
    final center = Offset(
      (ls.dx + rs.dx + lh.dx + rh.dx) / 4,
      (ls.dy + rs.dy + lh.dy + rh.dy) / 4,
    );

    // Pushes a point outwards from the center of mass to create an envelope
    Offset pushOut(Offset p, double dist) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len == 0) return p;
      return Offset(p.dx + (dx / len) * dist, p.dy + (dy / len) * dist);
    }

    final inflation = baseUnit * 0.45; // Creates the 'body' thickness

    // Define the coarse outer perimeter sequence
    List<Offset> rawPoints = [
      la, lk, lh,
      lw, le, ls,
      Offset(n.dx, n.dy - baseUnit * 0.7), // Top of head
      rs, re, rw,
      rh, rk, ra,
      Offset((la.dx + ra.dx) / 2, (lh.dy + rh.dy) / 2 + baseUnit * 0.3) // Crotch
    ];

    // Inflate the skeleton points to form an envelope
    List<Offset> inflated = rawPoints.map((p) => pushOut(p, inflation)).toList();

    // Smooth heavily to get the fluid, abstract Huawei-style curvy line
    List<Offset> smoothed = _chaikin(inflated, 5);

    Path path = Path();
    if (smoothed.isNotEmpty) {
      path.moveTo(smoothed.first.dx, smoothed.first.dy);
      for (int i = 1; i < smoothed.length; i++) {
        path.lineTo(smoothed[i].dx, smoothed[i].dy);
      }
      path.close();
    }
    return path;
  }

  static List<Offset> _chaikin(List<Offset> pts, int iterations) {
    if (pts.isEmpty) return pts;
    List<Offset> current = pts;
    for (int i = 0; i < iterations; i++) {
      List<Offset> next = [];
      for (int j = 0; j < current.length; j++) {
        Offset p1 = current[j];
        Offset p2 = current[(j + 1) % current.length];
        // 1/4 and 3/4 points on the segment create beautiful smooth curves
        next.add(Offset(p1.dx * 0.75 + p2.dx * 0.25, p1.dy * 0.75 + p2.dy * 0.25));
        next.add(Offset(p1.dx * 0.25 + p2.dx * 0.75, p1.dy * 0.25 + p2.dy * 0.75));
      }
      current = next;
    }
    return current;
  }
}
