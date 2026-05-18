import 'package:flutter/material.dart';

class ZoomLevelBadge extends StatelessWidget {
  final double zoomLevel;

  const ZoomLevelBadge({super.key, required this.zoomLevel});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${zoomLevel.toStringAsFixed(1)}×',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}
