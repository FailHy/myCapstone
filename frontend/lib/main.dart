import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'screens/main_navigation.dart';
import 'screens/registration_screen.dart';
import 'features/auth/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider()..checkAuthStatus(),
        ),
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
      // Daftarkan route untuk menghindari error
      routes: {
        '/main': (context) => const MainNavigation(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegistrationScreen(),
      },
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isAuthenticated) {
            return const MainNavigation();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
