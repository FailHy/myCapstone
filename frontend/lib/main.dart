import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation.dart';
import 'screens/training_screen.dart';
import 'screens/result_screen.dart';

void main() {
  runApp(const BiTriApp());
}

class BiTriApp extends StatelessWidget {
  const BiTriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiTri AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainNavigation(),
        '/training': (context) => const TrainingScreen(),
        '/result': (context) => const ResultScreen(),
      },
    );
  }
}
