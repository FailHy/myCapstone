import 'package:flutter/material.dart';
import '../widgets/custom_widgets.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo Placeholder
              const Icon(Icons.stream, size: 48, color: Colors.white),
              const SizedBox(height: 16),
              Text('BiTri AI', style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: 8),
              Text(
                'Your Personal Training Assistant',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Train smarter with AI-based movement evaluation',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 48),

              // Forms
              const TextField(
                decoration: InputDecoration(
                  hintText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined, color: Colors.white54),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline, color: Colors.white54),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 32),

              // CTA
              PrimaryButton(
                text: 'Login',
                onPressed:
                    () => Navigator.pushReplacementNamed(
                      context,
                      '/main',
                    ), // Route to Main (Home + BottomNav)
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text(
                    'New user? Register Here',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
