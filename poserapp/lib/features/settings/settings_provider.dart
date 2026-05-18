import 'package:flutter_riverpod/flutter_riverpod.dart';

final overlayOpacityProvider =
    NotifierProvider<_OverlayOpacityNotifier, double>(
  _OverlayOpacityNotifier.new,
);

class _OverlayOpacityNotifier extends Notifier<double> {
  @override
  double build() => 1.0;
  void set(double v) => state = v;
}

final countdownDurationProvider =
    NotifierProvider<_CountdownDurationNotifier, int>(
  _CountdownDurationNotifier.new,
);

class _CountdownDurationNotifier extends Notifier<int> {
  @override
  int build() => 3;
  void set(int v) => state = v;
}
