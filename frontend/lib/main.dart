import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme.dart'; 
import 'screens/login_screen.dart';
import 'screens/main_navigation.dart';
import 'features/auth/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuthStatus()),
      ],
      child: const BiTriApp(),
    ),
  );
}

class BiTriApp extends StatelessWidget {
  const BiTriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiTri AI',
      debugShowCheckedModeBanner: false,
      routes: {
        '/main': (context) => const MainNavigation(), // Pastikan import MainNavigation sudah benar
      },
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          // HAPUS pengecekan isLoading di sini.
          // Loading hanya akan muncul di dalam tombol "MASUK" saja.

          if (authProvider.isAuthenticated) {
            return const MainNavigation(); 
          }
          
          return const LoginScreen(); 
        },
      ),
    );
  }
}