import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'registration_screen.dart'; // Sesuaikan path jika berbeda
import '../widgets/custom_widgets.dart'; // Sesuaikan path jika berbeda
import '../features/auth/providers/auth_provider.dart'; // Sesuaikan path jika berbeda

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    // 1. Tutup keyboard saat tombol ditekan
    FocusScope.of(context).unfocus();

    // 2. Validasi input kosong
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

    // Simpan reference context saat ini sebelum melakukan proses asynchronous (await)
    final currentContext = context;

    // 3. Eksekusi fungsi login di provider
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    // 4. Penanganan setelah await
    // Jika SUCCESS (berhasil), kita TIDAK PERLU melakukan apa-apa di sini.
    // Provider akan memanggil notifyListeners() dan main.dart otomatis
    // mengganti halaman ini ke MainNavigation(). Menampilkan Snackbar
    // di layar yang sudah dibuang (unmounted) akan menyebabkan error.

    // Jika GAGAL, tampilkan pesan error
    if (!success) {
      // Pastikan context masih aktif sebelum menampilkan Snackbar
      if (!currentContext.mounted) return;

      ScaffoldMessenger.of(currentContext).showSnackBar(
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(), // Scroll natural
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min, // Menghindari overflow vertikal
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Icon(
                        Icons.stream,
                        size: 48,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'BiTri AI',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
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

                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: Colors.grey,
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        hintText: 'Password',
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: Colors.grey,
                        ),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 32),

                    Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        // loading indicator saat proses login berjalan
                        if (authProvider.isLoading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return PrimaryButton(
                          text: 'Login',
                          onPressed: _handleLogin,
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegistrationScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'New user? Register Here',
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
