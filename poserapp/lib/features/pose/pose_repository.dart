import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pose_category.dart';
import 'pose_template.dart';

class PoseRepository {
  final Map<PoseCategory, List<PoseTemplate>> _cache = {};

  Future<List<PoseTemplate>> getPosesForCategory(
    PoseCategory category,
    AssetBundle bundle,
  ) async {
    if (_cache.containsKey(category)) return _cache[category]!;

    try {
      final raw = await bundle.loadString(category.assetPath);
      final list = jsonDecode(raw) as List<dynamic>;
      final poses = list
          .map((e) => PoseTemplate.fromJson(e as Map<String, dynamic>, category))
          .toList();
      _cache[category] = poses;
      return poses;
    } catch (e) {
      debugPrint('PoseRepository: failed to load ${category.assetPath}: $e');
      return [];
    }
  }
}
