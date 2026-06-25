import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Otomatis mengambil data profil dari backend sesaat setelah layar dimuat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().fetchProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Pengguna'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        // KUNCI PERBAIKAN: Gunakan Consumer agar UI bereaksi saat nama/email sudah didapatkan
        child: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            return ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),

                // --- TAMPILKAN NAMA ASLI ---
                Center(
                  child: Text(
                    authProvider.userName.isEmpty
                        ? 'Memuat Profil...'
                        : authProvider.userName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // --- TAMPILKAN EMAIL ASLI ---
                Center(
                  child: Text(
                    authProvider.userEmail.isEmpty
                        ? '...'
                        : authProvider.userEmail,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),

                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Pengaturan Aplikasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Riwayat Latihan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HistoryScreen()),
                    );
                  },
                ),
                const SizedBox(height: 16),

                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Keluar',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    await authProvider.logout();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
