import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

void showSettingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opacity = ref.watch(overlayOpacityProvider);
    final duration = ref.watch(countdownDurationProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Reference overlay',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  Text(
                    '${(opacity * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white10,
                  trackHeight: 2,
                ),
                child: Slider(
                  value: opacity,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) =>
                      ref.read(overlayOpacityProvider.notifier).set(v),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Countdown duration',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Row(
                children: [3, 5, 10].map((s) {
                  final selected = duration == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(countdownDurationProvider.notifier)
                          .set(s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? Colors.transparent
                                : Colors.white24,
                          ),
                        ),
                        child: Text(
                          '${s}s',
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white60,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
