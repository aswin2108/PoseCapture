import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pose_category.dart';
import 'pose_provider.dart';
import 'pose_template.dart';

const _cardWidth = 80.0;
const _cardSpacing = 8.0;

// ---------------------------------------------------------------------------
// Carousel

class PoseCarousel extends ConsumerStatefulWidget {
  const PoseCarousel({super.key});

  @override
  ConsumerState<PoseCarousel> createState() => _PoseCarouselState();
}

class _PoseCarouselState extends ConsumerState<PoseCarousel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(int index) {
    if (!_scrollController.hasClients) return;
    final target = index * (_cardWidth + _cardSpacing);
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final posesAsync = ref.watch(activeCategoryPosesProvider);
    final activeIndex = ref.watch(activePoseIndexProvider);

    // Scroll to newly selected pose
    ref.listen(activePoseIndexProvider, (_, next) => _scrollTo(next));

    // Jump to start when category changes
    ref.listen<PoseCategory>(activeCategoryProvider, (_, _) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    return SizedBox(
      height: 100,
      child: posesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (poses) => ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: poses.length,
          separatorBuilder: (_, _) => const SizedBox(width: _cardSpacing),
          itemBuilder: (context, index) => _PoseCard(
            pose: poses[index],
            isActive: index == activeIndex,
            onTap: () => ref.read(activePoseIndexProvider.notifier).set(index),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card

class _PoseCard extends StatelessWidget {
  final PoseTemplate pose;
  final bool isActive;
  final VoidCallback onTap;

  const _PoseCard({
    required this.pose,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _cardWidth,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.white60 : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: CustomPaint(
                painter: _MiniSkeletonPainter(
                  landmarks: pose.landmarks,
                  color: isActive ? Colors.white : Colors.white54,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                pose.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            _DifficultyDot(difficulty: pose.difficulty),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Difficulty dot

class _DifficultyDot extends StatelessWidget {
  final String difficulty;
  const _DifficultyDot({required this.difficulty});

  Color get _color => switch (difficulty) {
        'easy'   => const Color(0xFF4CAF50),
        'medium' => const Color(0xFFFFC107),
        'hard'   => const Color(0xFFF44336),
        _        => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini skeleton painter — same bone set as PoseOverlayPainter, scaled to card

class _MiniSkeletonPainter extends CustomPainter {
  final Map<String, PoseLandmark> landmarks;
  final Color color;

  const _MiniSkeletonPainter({required this.landmarks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final (a, b) in kSkeletonConnections) {
      final lA = landmarks[a], lB = landmarks[b];
      if (lA == null || lB == null) continue;
      canvas.drawLine(
        Offset(lA.x * size.width, lA.y * size.height),
        Offset(lB.x * size.width, lB.y * size.height),
        linePaint,
      );
    }

    for (final lm in landmarks.values) {
      canvas.drawCircle(
        Offset(lm.x * size.width, lm.y * size.height),
        2.0,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniSkeletonPainter old) =>
      landmarks != old.landmarks || color != old.color;
}
