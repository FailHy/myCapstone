import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  late final Dio dio;

  // ===========================================================================
  // KONFIGURASI IP - Ganti sesuai network Anda
  // ===========================================================================
  static const String physicalDeviceIP = '10.20.27.95';

  static String get _baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';

    if (Platform.isAndroid) {
      return _isEmulator()
          ? 'http://10.20.27.95:8000'
          : 'http://$physicalDeviceIP:8000';
    }

    if (Platform.isIOS) {
      return _isSimulator()
          ? 'http://127.0.0.1:8000'
          : 'http://$physicalDeviceIP:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  static bool _isEmulator() {
    try {
      return Platform.environment['ANDROID_EMULATOR'] != null ||
          Platform.environment['ANDROID_SDK_ROOT'] != null;
    } catch (_) {
      return false;
    }
  }

  static bool _isSimulator() {
    try {
      return Platform.environment['SIMULATOR_DEVICE_NAME'] != null ||
          Platform.environment['SIMULATOR_MODEL_IDENTIFIER'] != null;
    } catch (_) {
      return false;
    }
  }

  ApiClient._internal() {
    final baseUrl = _baseUrl;

    // LOG PENTING: Hanya tampilkan saat inisialisasi
    if (kDebugMode) {
      debugPrint('🚀 [API] Initialized: $baseUrl');
      debugPrint('🚀 [API] Platform: ${Platform.operatingSystem}');
    }

    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl.trim(),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    // Interceptor simpel tapi informatif
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Sisipkan token JWT
          try {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('jwt_token');
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (_) {}

          // Log request (simpan untuk development)
          if (kDebugMode) {
            debugPrint('📡 ${options.method} ${options.uri.path}');
          }

          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint(
              '✅ ${response.statusCode} ${response.requestOptions.uri.path}',
            );
          }
          return handler.next(response);
        },
        onError: (e, handler) {
          if (kDebugMode) {
            _logError(e);
          }
          return handler.next(e);
        },
      ),
    );
  }

  // Helper error logging yang rapih
  void _logError(DioException e) {
    final path = e.requestOptions.uri.path;
    final statusCode = e.response?.statusCode;

    debugPrint('❌ [$statusCode] $path - ${e.type.name}');

    // Hanya tampilkan detail untuk error tertentu
    if (e.type == DioExceptionType.connectionError) {
      debugPrint('   💡 Cek: IP, pada api_clien dan training_service');
    } else if (e.type == DioExceptionType.badResponse && e.response != null) {
      debugPrint('   📄 ${e.response?.data}');
    }
  }
}
