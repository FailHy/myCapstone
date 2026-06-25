import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Utility untuk mengonversi format kamera Android (YUV_420_888)
/// menjadi NV21 yang dibutuhkan ML Kit.
///
/// Kompatibilitas yang ditangani:
/// • Samsung  — bytesPerRow sering lebih besar dari width (ada padding)
/// • Xiaomi   — UV plane bisa sudah interleaved (pixelStride=2, shared buffer)
/// • Infinix  — pixelStride=1 (UV terpisah murni)
/// • Oppo/Vivo/Realme — variasi padding dan pixelStride
class ImageConverter {
  // ------------------------------------------------------------------
  // PUBLIC API
  // ------------------------------------------------------------------

  /// Konversi [CameraImage] format YUV_420_888 → Uint8List NV21.
  ///
  /// Mengembalikan `null` jika:
  /// • planes < 3
  /// • dimensi gambar 0
  /// • terjadi exception saat konversi
  static Uint8List? yuv420ToNV21(CameraImage image) {
    // ── Validasi planes ──────────────────────────────────────────────
    if (image.planes.length < 3) {
      debugPrint(
        '[ImageConverter] ❌ Plane count tidak cukup: ${image.planes.length}. '
        'Diperlukan minimal 3.',
      );
      return null;
    }

    final int width  = image.width;
    final int height = image.height;

    if (width == 0 || height == 0) {
      debugPrint('[ImageConverter] ❌ Dimensi gambar tidak valid: ${width}x$height');
      return null;
    }

    // ── Logging detail ────────────────────────────────────────────────
    debugPrint(
      '[ImageConverter] 📷 Konversi frame: ${width}x$height | '
      'planes=${image.planes.length} | '
      'yStride=${image.planes[0].bytesPerRow} | '
      'uvStride=${image.planes[1].bytesPerRow} | '
      'uvPixelStride=${image.planes[1].bytesPerPixel}',
    );

    try {
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      // ── Fast Path: UV sudah interleaved (Samsung / Xiaomi) ───────────
      // Tanda-tanda: plane[1] dan plane[2] berbagi buffer yang sama
      // dengan pixelStride = 2. Dalam hal ini, NV21 dapat dibangun
      // dengan hanya menukar urutan V/U dari plane[2].
      if (uvPixelStride == 2) {
        return _convertInterleaved(image, width, height);
      }

      // ── Normal Path: UV terpisah (Infinix / Tecno / most MediaTek) ──
      return _convertPlanar(image, width, height);
    } catch (e, st) {
      debugPrint('[ImageConverter] ❌ Exception saat konversi: $e\n$st');
      return null;
    }
  }

  // ------------------------------------------------------------------
  // PRIVATE HELPERS
  // ------------------------------------------------------------------

  /// Fast path — UV sudah interleaved di plane[1] dengan pixelStride=2.
  /// Cukup copy Y, lalu copy plane[2] (VU order) langsung ke buffer.
  static Uint8List _convertInterleaved(
      CameraImage image, int width, int height) {
    final int ySize  = width * height;
    final int uvSize = (width ~/ 2) * (height ~/ 2) * 2;
    final nv21 = Uint8List(ySize + uvSize);

    // 1. Y plane — dengan handle padding
    _copyYPlane(nv21, image.planes[0], width, height, 0);

    // 2. VU interleaved — plane[2] adalah V, berdampingan dengan U di memori.
    //    Kita copy langsung sejumlah uvSize byte mulai dari offset 0 plane[2].
    final Uint8List vPlane = image.planes[2].bytes;
    final int copyLen = uvSize.clamp(0, vPlane.length);
    nv21.setRange(ySize, ySize + copyLen, vPlane, 0);

    debugPrint('[ImageConverter] ✅ Fast-path interleaved selesai');
    return nv21;
  }

  /// Normal path — U dan V plane benar-benar terpisah (pixelStride=1).
  /// Harus di-interleave secara manual: V0, U0, V1, U1, ...
  static Uint8List _convertPlanar(
      CameraImage image, int width, int height) {
    final int ySize  = width * height;
    final int uvSize = (width ~/ 2) * (height ~/ 2) * 2;
    final nv21 = Uint8List(ySize + uvSize);

    // 1. Y plane
    _copyYPlane(nv21, image.planes[0], width, height, 0);

    // 2. Interleave V dan U secara manual
    final Uint8List uBytes      = image.planes[1].bytes;
    final Uint8List vBytes      = image.planes[2].bytes;
    final int       uvRowStride = image.planes[1].bytesPerRow;
    final int       vRowStride  = image.planes[2].bytesPerRow;
    final int       uvPxStride  = image.planes[1].bytesPerPixel ?? 1;
    final int       vPxStride   = image.planes[2].bytesPerPixel ?? 1;

    final int uvHeight = height ~/ 2;
    final int uvWidth  = width  ~/ 2;

    int outIdx = ySize;
    for (int row = 0; row < uvHeight; row++) {
      final int uRowBase = row * uvRowStride;
      final int vRowBase = row * vRowStride;
      for (int col = 0; col < uvWidth; col++) {
        final int uIdx = uRowBase + col * uvPxStride;
        final int vIdx = vRowBase + col * vPxStride;

        // Bounds guard — jangan crash pada device dengan buffer ganjil
        nv21[outIdx++] = vIdx < vBytes.length ? vBytes[vIdx] : 128;
        nv21[outIdx++] = uIdx < uBytes.length ? uBytes[uIdx] : 128;
      }
    }

    debugPrint('[ImageConverter] ✅ Normal-path planar selesai');
    return nv21;
  }

  /// Salin Y plane ke [dest] mulai [destOffset], dengan handle bytesPerRow padding.
  static void _copyYPlane(
    Uint8List dest,
    Plane yPlane,
    int width,
    int height,
    int destOffset,
  ) {
    final Uint8List src      = yPlane.bytes;
    final int       rowStride = yPlane.bytesPerRow;

    if (rowStride == width) {
      // Tidak ada padding — salin sekaligus
      final int len = (width * height).clamp(0, src.length);
      dest.setRange(destOffset, destOffset + len, src);
    } else {
      // Ada padding (rowStride > width) — salin per baris
      int out = destOffset;
      for (int row = 0; row < height; row++) {
        final int srcStart = row * rowStride;
        final int srcEnd   = (srcStart + width).clamp(0, src.length);
        final int copyLen  = srcEnd - srcStart;
        dest.setRange(out, out + copyLen, src, srcStart);
        out += width;
      }
    }
  }
}