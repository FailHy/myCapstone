import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/custom_widgets.dart'; // Widget custom Anda
import '../features/auth/providers/auth_provider.dart'; // Auth Provider kita

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controller untuk mengambil teks dari form
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Logika ketika tombol Login ditekan
  void _handleLogin() async {
    // Sembunyikan keyboard saat tombol ditekan
    FocusScope.of(context).unfocus();

    // Pastikan email dan password tidak kosong (Validasi sederhana)
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email dan Password tidak boleh kosong!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    
    // Panggil API Login
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      // BERHASIL!
      // Kita TIDAK PERLU Navigator.pushReplacementNamed di sini.
      // File main.dart akan mendeteksi token dan otomatis memindahkan layar.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login Berhasil!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // GAGAL
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Tambahkan warna background jika sebelumnya diatur di tema
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      body: SafeArea(
        child: Center(
          // KUNCI PERBAIKAN OVERFLOW: SingleChildScrollView
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Placeholder
                  const Center(child: Icon(Icons.stream, size: 48, color: Colors.blueAccent)),
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
                  TextField(
                    controller: _emailController, // Hubungkan controller
                    decoration: const InputDecoration(
                      hintText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: Colors.grey),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController, // Hubungkan controller
                    decoration: const InputDecoration(
                      hintText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline, color: Colors.grey),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 32),

                  // CTA
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      // Tampilkan loading jika sedang memproses API
                      if (authProvider.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      // Tampilkan tombol asli Anda jika tidak loading
                      return PrimaryButton(
                        text: 'Login',
                        onPressed: _handleLogin, // Panggil fungsi di atas
                      );
                    },
                  ),
                  const SizedBox(height: 24), // Pengganti Spacer() agar tidak error di dalam ScrollView
                  
                  Center(
                    child: TextButton(
                      onPressed: () {},
                      child: const Text(
                        'New user? Register Here',
                        style: TextStyle(color: Colors.blueGrey), // Sesuaikan warnanya
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}