import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class ApiClient {
  // 1. SINGLETON PATTERN: Memastikan hanya ada 1 instance Dio di memori
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;

  // ===========================================================================
  // CONFIGURATION
  // Pastikan IP ini sesuai dengan IPv4 (wlp2s0 / Wi-Fi) di laptop Anda.
  // ===========================================================================
  static const String physicalDeviceIP = '10.86.59.195';

  static String get _baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';

    if (Platform.isAndroid) {
      return _isEmulator()
          ? 'http://10.0.2.2:8000'
          : 'http://$physicalDeviceIP:8000';
    }

    if (Platform.isIOS) {
      return 'http://$physicalDeviceIP:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  // Helper untuk mendeteksi apakah aplikasi berjalan di Emulator Android
  static bool _isEmulator() {
    try {
      return Platform.environment['ANDROID_EMULATOR'] != null ||
          Platform.environment['ANDROID_SDK_ROOT'] != null;
    } catch (_) {
      return false;
    }
  }

  // 2. CONSTRUCTOR PRIVATE
  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // 3. INTERCEPTORS: Middleware untuk setiap HTTP Request/Response
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (kDebugMode) {
            debugPrint('📡 [REQ] ${options.method} ${options.uri.path}');
          }

          // Otomatis menyisipkan JWT Token (jika ada) ke setiap request
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('jwt_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint(
              '✅ [RES] ${response.statusCode} : ${response.requestOptions.uri.path}',
            );
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          if (kDebugMode) {
            debugPrint('❌ [ERR] ${e.type} pada ${e.requestOptions.uri.path}');
            _diagnoseError(e); // Panggil helper log
          }
          return handler.next(e);
        },
      ),
    );
  }

  // Helper untuk mencetak diagnosa error yang rapi
  void _diagnoseError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        debugPrint(
          '💡 DIAGNOSA: Timeout. Cek koneksi WiFi dan pastikan FastAPI berjalan.',
        );
        break;
      case DioExceptionType.connectionError:
        debugPrint(
          '💡 DIAGNOSA: Connection Refused. Pastikan physicalDeviceIP benar & server menggunakan --host 0.0.0.0.',
        );
        break;
      case DioExceptionType.badResponse:
        debugPrint(
          '💡 DIAGNOSA: Ditolak Server (Status ${e.response?.statusCode}). Detail: ${e.response?.data}',
        );
        break;
      default:
        debugPrint(
          '💡 DIAGNOSA: Terjadi kesalahan jaringan lainnya (${e.message}).',
        );
    }
  }
}
