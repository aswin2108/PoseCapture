import 'dart:math' show sqrt;

import 'pose_template.dart';

class PoseMatcher {
  // Limb-direction pairs used for angle scoring. Intentionally a strict subset
  // of kSkeletonConnections — the transverse bars (shoulder↔shoulder,
  // hip↔hip) measure body width, not limb direction, and would skew the
  // cosine-similarity score toward lateral displacement rather than pose shape.
  static const _bonePairs = [
    ('left_shoulder', 'left_elbow'),
    ('left_elbow', 'left_wrist'),
    ('right_shoulder', 'right_elbow'),
    ('right_elbow', 'right_wrist'),
    ('left_shoulder', 'left_hip'),
    ('right_shoulder', 'right_hip'),
    ('left_hip', 'left_knee'),
    ('left_knee', 'left_ankle'),
    ('right_hip', 'right_knee'),
    ('right_knee', 'right_ankle'),
  ];

  static double score(
    Map<String, PoseLandmark> user,
    Map<String, PoseLandmark> reference,
  ) {
    double total = 0;
    int count = 0;

    for (final (a, b) in _bonePairs) {
      final uA = user[a], uB = user[b];
      final rA = reference[a], rB = reference[b];
      if (uA == null || uB == null || rA == null || rB == null) continue;

      final uVec = _normalize(uA, uB);
      final rVec = _normalize(rA, rB);
      // Skip degenerate bones (coincident landmarks) — their zero vector
      // produces dot = 0, which incorrectly counts as a 90° angle miss.
      if (uVec == (0.0, 0.0) || rVec == (0.0, 0.0)) continue;
      final dot = _dot(uVec, rVec).clamp(-1.0, 1.0);
      total += dot;
      count++;
    }

    if (count == 0) return 0.0;
    // dot product of unit vectors is in [-1, 1]; remap to [0, 1]
    return ((total / count + 1.0) / 2.0).clamp(0.0, 1.0);
  }

  static (double, double) _normalize(PoseLandmark a, PoseLandmark b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return (0.0, 0.0);
    return (dx / len, dy / len);
  }

  static double _dot((double, double) v1, (double, double) v2) =>
      v1.$1 * v2.$1 + v1.$2 * v2.$2;
}
