import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  late Dio dio;
  
  // PERHATIAN: 
  // Ganti IP ini dengan IP Local Laptop Anda jika di-run di HP Fisik (misal: 192.168.1.15)
  // Gunakan 10.0.2.2 jika di-run menggunakan Emulator Android Studio
  static const String baseUrl = 'http://192.168.15.46:8000';

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    // Interceptor untuk otomatis menyisipkan JWT Token di setiap request
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('jwt_token');
        
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        // Tangani error token expired (401) secara global di sini
        if (e.response?.statusCode == 401) {
          // TODO: Arahkan paksa user ke LoginScreen
        }
        return handler.next(e);
      },
    ));
  }
}