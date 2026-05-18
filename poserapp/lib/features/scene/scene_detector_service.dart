import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;

import '../../core/ml/camera_ml_utils.dart';
import '../pose/pose_category.dart';

const _intervalSeconds = 5;

// -------------------------------------------------------------------------
// Label sets — ML Kit returns free-form English strings
// -------------------------------------------------------------------------

const _fitnessLabels = {
  'gym', 'exercise', 'fitness', 'bodybuilding', 'weight training',
  'dumbbell', 'barbell',
};
const _sportsLabels = {
  'sport', 'sports', 'running', 'jumping', 'soccer', 'basketball',
  'skateboard', 'athletics', 'tennis', 'swimming', 'football',
};
const _fashionLabels = {
  'fashion', 'model', 'clothing', 'dress', 'style', 'beauty', 'outfit',
};
const _casualLabels = {
  'beach', 'park', 'nature', 'outdoor', 'outdoors', 'street',
  'city', 'garden', 'landscape', 'travel',
};

PoseCategory _mapLabels(List<mlkit.ImageLabel> labels) {
  final names = labels.map((l) => l.label.toLowerCase()).toSet();

  if (names.intersection(_fitnessLabels).isNotEmpty) return PoseCategory.fitness;
  if (names.intersection(_sportsLabels).isNotEmpty) return PoseCategory.sports;
  if (names.intersection(_fashionLabels).isNotEmpty) return PoseCategory.fashion;
  if (names.intersection(_casualLabels).isNotEmpty) return PoseCategory.casual;

  return PoseCategory.casual;
}

// -------------------------------------------------------------------------

class SceneDetectorService {
  final _labeler = mlkit.ImageLabeler(
    options: mlkit.ImageLabelerOptions(confidenceThreshold: 0.55),
  );

  DateTime? _lastRun;
  bool _busy = false;
  bool _formatWarningLogged = false;

  /// Returns a detected [PoseCategory] at most once per [_intervalSeconds],
  /// or null if it is too soon, already busy, or the image format is unsupported.
  /// Always returns null for the front camera — its category is set by flipCamera().
  Future<PoseCategory?> maybeDetect(
    CameraImage image,
    CameraDescription camera,
  ) async {
    // Front camera is always selfie; flipCamera() already sets the category.
    // Skip ML Kit entirely — no work done, rate-limit not consumed.
    if (camera.lensDirection == CameraLensDirection.front) return null;

    final now = DateTime.now();
    if (_lastRun != null &&
        now.difference(_lastRun!).inSeconds < _intervalSeconds) {
      return null;
    }
    if (_busy) return null;
    _busy = true;
    _lastRun = now;

    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        if (!_formatWarningLogged) {
          _formatWarningLogged = true;
          debugPrint(
            'SceneDetector: unsupported pixel format '
            '0x${image.format.raw.toRadixString(16)} — '
            'scene detection is disabled on this device',
          );
        }
        return null;
      }

      final labels = await _labeler.processImage(inputImage);
      return _mapLabels(labels);
    } catch (e) {
      debugPrint('SceneDetector error: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  mlkit.InputImage? _buildInputImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotation = mlkit.InputImageRotationValue.fromRawValue(
          camera.sensorOrientation,
        ) ??
        mlkit.InputImageRotation.rotation0deg;
    final size = Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isAndroid) {
      final nv21 = toNv21(image);
      if (nv21 != null) {
        return mlkit.InputImage.fromBytes(
          bytes: nv21,
          metadata: mlkit.InputImageMetadata(
            size: size,
            rotation: rotation,
            format: mlkit.InputImageFormat.nv21,
            bytesPerRow: image.width,
          ),
        );
      }
    }

    final format =
        mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      if (!_formatWarningLogged) {
        _formatWarningLogged = true;
        debugPrint(
          'SceneDetector: unsupported pixel format '
          '0x${image.format.raw.toRadixString(16)} — '
          'scene detection is disabled on this device',
        );
      }
      return null;
    }

    return mlkit.InputImage.fromBytes(
      bytes: concatenateCameraPlanes(image.planes),
      metadata: mlkit.InputImageMetadata(
        size: size,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void dispose() => _labeler.close();
}
