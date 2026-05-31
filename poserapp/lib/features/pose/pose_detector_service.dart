import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;

import '../../core/ml/camera_ml_utils.dart';
import 'pose_template.dart';

/// Maps ML Kit landmark types to our JSON key names.
const _mlTypeToName = {
  mlkit.PoseLandmarkType.nose:          'nose',
  mlkit.PoseLandmarkType.leftEar:       'left_ear',
  mlkit.PoseLandmarkType.rightEar:      'right_ear',
  mlkit.PoseLandmarkType.leftShoulder:  'left_shoulder',
  mlkit.PoseLandmarkType.rightShoulder: 'right_shoulder',
  mlkit.PoseLandmarkType.leftElbow:     'left_elbow',
  mlkit.PoseLandmarkType.rightElbow:    'right_elbow',
  mlkit.PoseLandmarkType.leftWrist:     'left_wrist',
  mlkit.PoseLandmarkType.rightWrist:    'right_wrist',
  mlkit.PoseLandmarkType.leftHip:       'left_hip',
  mlkit.PoseLandmarkType.rightHip:      'right_hip',
  mlkit.PoseLandmarkType.leftKnee:      'left_knee',
  mlkit.PoseLandmarkType.rightKnee:     'right_knee',
  mlkit.PoseLandmarkType.leftAnkle:     'left_ankle',
  mlkit.PoseLandmarkType.rightAnkle:    'right_ankle',
};

class PoseDetectorService {
  final mlkit.PoseDetector _detector = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.stream,
    ),
  );

  // Time-based throttle: process at most once per 80ms (~12fps) regardless
  // of what the camera's actual frame rate is (30fps, 60fps, etc.).
  // Index-based throttle (% 3) doubles the load on 60fps devices.
  static const _kThrottleMs = 80;
  bool _busy = false;
  DateTime? _lastProcessed;
  bool _formatWarningLogged = false;

  /// Returns normalized display-space landmarks, or null if frame is skipped.
  Future<Map<String, PoseLandmark>?> processFrame(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final now = DateTime.now();
    if (_lastProcessed != null &&
        now.difference(_lastProcessed!).inMilliseconds < _kThrottleMs) {
      return null;
    }
    if (_busy) return null;
    _busy = true;
    _lastProcessed = now;

    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        if (!_formatWarningLogged) {
          _formatWarningLogged = true;
          debugPrint(
            'PoseDetector: unsupported pixel format '
            '0x${image.format.raw.toRadixString(16)} — '
            'pose detection is disabled on this device',
          );
        }
        return null;
      }

      final poses = await _detector.processImage(inputImage);
      // Return empty map (not null) so the caller knows a real frame ran but
      // found no one — null is reserved for "frame was skipped".
      if (poses.isEmpty) return {};

      return _toLandmarkMap(poses.first, image, camera);
    } catch (e) {
      debugPrint('PoseDetector error: $e');
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

    // On Android the camera plugin delivers YUV_420_888 (3 separate planes).
    // Naively concatenating planes is wrong when bytesPerPixel > 1 or when
    // rows are padded — convert to NV21 which ML Kit handles reliably.
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

    // iOS (or Android single-plane fallback): use the raw format directly.
    final format =
        mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      if (!_formatWarningLogged) {
        _formatWarningLogged = true;
        debugPrint(
          'PoseDetector: unsupported pixel format '
          '0x${image.format.raw.toRadixString(16)} — '
          'pose detection is disabled on this device',
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

  Map<String, PoseLandmark> _toLandmarkMap(
    mlkit.Pose pose,
    CameraImage image,
    CameraDescription camera,
  ) {
    final result = <String, PoseLandmark>{};
    for (final entry in _mlTypeToName.entries) {
      final mlLm = pose.landmarks[entry.key];
      if (mlLm == null) continue;
      result[entry.value] = _transformToDisplay(
        mlLm.x,
        mlLm.y,
        image.width.toDouble(),
        image.height.toDouble(),
        camera.sensorOrientation,
        camera.lensDirection,
      );
    }
    return result;
  }

  /// Converts ML Kit pixel coords (image space) → normalized display space.
  PoseLandmark _transformToDisplay(
    double px,
    double py,
    double imgW,
    double imgH,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    double nx, ny;

    if (Platform.isAndroid) {
      // ML Kit processes the image after rotating it by sensorOrientation.
      // Therefore, the coordinates returned are ALREADY in the rotated space.
      final bool isRotated = sensorOrientation == 90 || sensorOrientation == 270;
      final double rotatedW = isRotated ? imgH : imgW;
      final double rotatedH = isRotated ? imgW : imgH;

      nx = px / rotatedW;
      ny = py / rotatedH;
      
      if (lensDirection == CameraLensDirection.front) {
        nx = 1.0 - nx;
      }
    } else {
      // iOS: camera plugin delivers the image ALREADY in display orientation.
      nx = px / imgW;
      ny = py / imgH;
      if (lensDirection == CameraLensDirection.front) {
        nx = 1.0 - nx;
      }
    }

    return PoseLandmark(x: nx.clamp(0.0, 1.0), y: ny.clamp(0.0, 1.0));
  }

  void dispose() => _detector.close();
}
