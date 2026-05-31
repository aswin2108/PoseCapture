import 'pose_category.dart';

/// Canonical skeleton adjacency list shared by overlay painter and carousel.
/// Each tuple is (proximal landmark name, distal landmark name).
const kSkeletonConnections = [
  ('left_shoulder', 'right_shoulder'),
  ('left_shoulder', 'left_elbow'),
  ('left_elbow', 'left_wrist'),
  ('right_shoulder', 'right_elbow'),
  ('right_elbow', 'right_wrist'),
  ('left_shoulder', 'left_hip'),
  ('right_shoulder', 'right_hip'),
  ('left_hip', 'right_hip'),
  ('left_hip', 'left_knee'),
  ('left_knee', 'left_ankle'),
  ('right_hip', 'right_knee'),
  ('right_knee', 'right_ankle'),
];

class PoseLandmark {
  final double x;
  final double y;

  const PoseLandmark({required this.x, required this.y});

  factory PoseLandmark.fromJson(Map<String, dynamic> json) => PoseLandmark(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );
}

class PoseTemplate {
  final String id;
  final String name;
  final PoseCategory category;
  final String camera;
  final String difficulty;
  final String svgPath;
  final String svgViewBox;
  final Map<String, PoseLandmark> landmarks;

  const PoseTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.camera,
    required this.difficulty,
    required this.svgPath,
    required this.svgViewBox,
    required this.landmarks,
  });

  factory PoseTemplate.fromJson(
    Map<String, dynamic> json,
    PoseCategory category,
  ) {
    final landmarksJson = json['landmarks'] as Map<String, dynamic>? ?? {};
    return PoseTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      category: category,
      camera: (json['camera'] as String?) ?? 'both',
      difficulty: (json['difficulty'] as String?) ?? 'easy',
      svgPath: (json['svgPath'] as String?) ?? '',
      svgViewBox: (json['svgViewBox'] as String?) ?? '0 0 100 100',
      landmarks: landmarksJson.map(
        (k, v) => MapEntry(k, PoseLandmark.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}
