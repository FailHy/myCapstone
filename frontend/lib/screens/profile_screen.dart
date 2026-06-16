import 'package:flutter/material.dart';
import '../widgets/custom_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Avatar & Username
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('Alex Kucay', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 32),

            // User Stats
            const Row(
              children: [
                StatsCard(title: 'Days Trained', value: '14'),
                SizedBox(width: 16),
                StatsCard(title: 'Avg. Exercises', value: '3/day'),
              ],
            ),
            const SizedBox(height: 32),

            // History List
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: 5,
                itemBuilder: (context, index) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.history, color: Colors.white),
                    ),
                    title: const Text(
                      'Biceps Training',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Yesterday • 85% Accuracy',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
