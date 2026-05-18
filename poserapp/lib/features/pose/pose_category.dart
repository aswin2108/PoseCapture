enum PoseCategory {
  casual,
  fashion,
  fitness,
  sports,
  selfie;

  String get displayName => switch (this) {
        PoseCategory.casual  => 'Casual',
        PoseCategory.fashion => 'Fashion',
        PoseCategory.fitness => 'Fitness',
        PoseCategory.sports  => 'Sports',
        PoseCategory.selfie  => 'Selfie',
      };

  String get assetPath => switch (this) {
        PoseCategory.casual  => 'assets/poses/casual.json',
        PoseCategory.fashion => 'assets/poses/fashion_portrait.json',
        PoseCategory.fitness => 'assets/poses/fitness_muscles.json',
        PoseCategory.sports  => 'assets/poses/sports_action.json',
        PoseCategory.selfie  => 'assets/poses/selfie_front.json',
      };
}
