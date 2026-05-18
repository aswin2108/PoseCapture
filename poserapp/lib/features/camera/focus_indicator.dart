import 'package:flutter/material.dart';

class FocusRing extends StatelessWidget {
  final Offset point;
  final bool visible;
  final Animation<double> scaleAnimation;

  const FocusRing({
    super.key,
    required this.point,
    required this.visible,
    required this.scaleAnimation,
  });

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: point.dx - _size / 2,
      top: point.dy - _size / 2,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: AnimatedBuilder(
            animation: scaleAnimation,
            builder: (_, _) => Transform.scale(
              scale: scaleAnimation.value,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFFFD60A),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
