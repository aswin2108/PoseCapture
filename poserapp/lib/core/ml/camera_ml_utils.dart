import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Concatenates all YUV planes from a [CameraImage] into a contiguous byte
/// buffer, which is the layout ML Kit's `InputImage.fromBytes` expects for
/// multi-plane formats on iOS (BGRA etc.).
Uint8List concatenateCameraPlanes(List<Plane> planes) {
  final buf = WriteBuffer();
  for (final p in planes) {
    buf.putUint8List(p.bytes);
  }
  return buf.done().buffer.asUint8List();
}

/// Converts a 3-plane `YUV_420_888` [CameraImage] (standard Android camera
/// plugin output) to the `NV21` byte layout that ML Kit handles most reliably
/// on Android.
///
/// Android's `YUV_420_888` provides three separate planes:
///   plane[0] — Y  (full res, bytesPerRow may include padding)
///   plane[1] — U/Cb (half res, bytesPerPixel is often 2 when semi-planar)
///   plane[2] — V/Cr (half res, same stride as U)
///
/// NV21 requires:
///   [Y row-stripped] + [VU interleaved half-res]
///
/// Naively concatenating planes is wrong when `bytesPerPixel > 1` or when
/// row padding exists — this is the common silent failure mode on Pixel phones.
///
/// Returns `null` when the image doesn't have the expected 3-plane structure
/// (e.g. JPEG single-plane stream), in which case the caller should fall back
/// to the raw format path.
Uint8List? toNv21(CameraImage image) {
  if (image.planes.length < 3) return null;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1]; // Cb
  final vPlane = image.planes[2]; // Cr

  final w = image.width;
  final h = image.height;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final nv21 = Uint8List(w * h + (w ~/ 2) * (h ~/ 2) * 2);

  // --- Y plane: strip row padding ---
  int pos = 0;
  for (int row = 0; row < h; row++) {
    nv21.setRange(pos, pos + w, yPlane.bytes, row * yPlane.bytesPerRow);
    pos += w;
  }

  // --- VU interleaved (NV21 order) ---
  for (int row = 0; row < h ~/ 2; row++) {
    for (int col = 0; col < w ~/ 2; col++) {
      final vIdx = row * vPlane.bytesPerRow + col * uvPixelStride;
      final uIdx = row * uPlane.bytesPerRow + col * uvPixelStride;
      nv21[pos++] = vIdx < vPlane.bytes.length ? vPlane.bytes[vIdx] : 0;
      nv21[pos++] = uIdx < uPlane.bytes.length ? uPlane.bytes[uIdx] : 0;
    }
  }

  return nv21;
}
