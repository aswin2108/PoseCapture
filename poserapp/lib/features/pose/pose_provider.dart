import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pose_category.dart';
import 'pose_matcher.dart';
import 'pose_repository.dart';
import 'pose_template.dart';

// ---------------------------------------------------------------------------
// Active category
// ---------------------------------------------------------------------------

final activeCategoryProvider =
    NotifierProvider<_ActiveCategoryNotifier, PoseCategory>(
  _ActiveCategoryNotifier.new,
);

class _ActiveCategoryNotifier extends Notifier<PoseCategory> {
  @override
  PoseCategory build() => PoseCategory.casual;
  void set(PoseCategory value) => state = value;
}

// True when the user has manually tapped a chip, suppressing scene auto-detection
// until the next camera flip (which resets this to false).
final categoryManuallySetProvider =
    NotifierProvider<_CategoryManuallySetNotifier, bool>(
  _CategoryManuallySetNotifier.new,
);

class _CategoryManuallySetNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

// ---------------------------------------------------------------------------
// Pose repository (singleton, caches JSON)
// ---------------------------------------------------------------------------

final _poseRepositoryProvider = Provider((ref) => PoseRepository());

// Poses for the active category, loaded from JSON assets
final activeCategoryPosesProvider = FutureProvider<List<PoseTemplate>>((ref) {
  final category = ref.watch(activeCategoryProvider);
  final repo = ref.watch(_poseRepositoryProvider);
  return repo.getPosesForCategory(category, rootBundle);
});

// ---------------------------------------------------------------------------
// Active pose index within current category
// ---------------------------------------------------------------------------

final activePoseIndexProvider =
    NotifierProvider<_ActivePoseIndexNotifier, int>(
  _ActivePoseIndexNotifier.new,
);

class _ActivePoseIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int value) => state = value;
}

// Currently displayed reference pose template
final activePoseProvider = Provider<PoseTemplate?>((ref) {
  final poses = ref.watch(activeCategoryPosesProvider).asData?.value;
  if (poses == null || poses.isEmpty) return null;
  final index = ref.watch(activePoseIndexProvider);
  return poses[index.clamp(0, poses.length - 1)];
});

// ---------------------------------------------------------------------------
// Detected user landmarks — updated by the camera image stream
// ---------------------------------------------------------------------------

final detectedLandmarksProvider =
    NotifierProvider<_DetectedLandmarksNotifier, Map<String, PoseLandmark>?>(
  _DetectedLandmarksNotifier.new,
);

class _DetectedLandmarksNotifier
    extends Notifier<Map<String, PoseLandmark>?> {
  @override
  Map<String, PoseLandmark>? build() => null;
  void set(Map<String, PoseLandmark>? value) => state = value;
}

// ---------------------------------------------------------------------------
// Real-time similarity score 0.0–1.0
// ---------------------------------------------------------------------------

final poseScoreProvider = Provider<double>((ref) {
  final user = ref.watch(detectedLandmarksProvider);
  final pose = ref.watch(activePoseProvider);
  if (user == null || pose == null) return 0.0;
  return PoseMatcher.score(user, pose.landmarks);
});

