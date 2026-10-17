import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../widgets/sign_widgets.dart';
import 'sign_detail_screen.dart';

String _unitTitle(String unit) {
  final m = RegExp(r'^unit(\d+)$', caseSensitive: false).firstMatch(unit);
  return m != null ? 'Unit ${m.group(1)}' : unit;
}

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('signs')
        .orderBy('order')
        .snapshots();

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final signs = snapshot.data!.docs.map(Sign.fromFirestore).toList();

          // Group by unit, keeping the order from Firestore.
          final Map<String, List<Sign>> byUnit = {};
          for (final s in signs) {
            byUnit.putIfAbsent(s.unit, () => []).add(s);
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text('Learn'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                ],
              ),
              for (final entry in byUnit.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      _unitTitle(entry.key),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 140,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SignTile(sign: entry.value[index]),
                      childCount: entry.value.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _SignTile extends StatelessWidget {
  final Sign sign;

  const _SignTile({required this.sign});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SignDetailScreen(sign: sign)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              sign.name,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            DifficultyDots(level: sign.difficulty),
          ],
        ),
      ),
    );
  }
}
