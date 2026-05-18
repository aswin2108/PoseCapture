import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pose_category.dart';
import 'pose_provider.dart';

class CategorySelector extends ConsumerWidget {
  const CategorySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCategoryProvider);

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: PoseCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = PoseCategory.values[i];
          final selected = cat == active;
          return _Chip(
            label: cat.displayName,
            selected: selected,
            onTap: selected
                ? null
                : () {
                    ref.read(categoryManuallySetProvider.notifier).set(true);
                    ref.read(activePoseIndexProvider.notifier).set(0);
                    ref.read(activeCategoryProvider.notifier).set(cat);
                  },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(17),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
