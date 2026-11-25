import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/spot.dart';

/// Le macchie vive: ondeggiano col tempo, ma senza saltare quando partono
/// e senza uscire dal loro riquadro.
void main() {
  const rect = Rect.fromLTWH(0, 0, 200, 200);
  const seed = 'https://example.com/cover.jpg';

  List<Offset> samples(Path p) => [
    for (final m in p.computeMetrics())
      for (var d = 0.0; d < m.length; d += m.length / 24)
        m.getTangentForOffset(d)!.position,
  ];

  test('a tempo zero la macchia e\' quella ferma: niente scatto', () {
    final still = samples(spotPath(rect, seed));
    final zero = samples(spotPath(rect, seed, time: 0));
    for (var i = 0; i < still.length; i++) {
      expect((still[i] - zero[i]).distance, lessThan(0.01));
    }
  });

  test('col tempo cambia forma, restando nel riquadro', () {
    final a = spotPath(rect, seed, time: 0);
    final b = spotPath(rect, seed, time: 2.5);
    final moved = [
      for (final (i, p) in samples(a).indexed) (p - samples(b)[i]).distance,
    ].reduce((x, y) => x > y ? x : y);
    expect(moved, greaterThan(2));
    final bounds = b.getBounds();
    expect(bounds.left, closeTo(0, 0.5));
    expect(bounds.right, closeTo(200, 0.5));
    expect(bounds.top, closeTo(0, 0.5));
    expect(bounds.bottom, closeTo(200, 0.5));
  });

  testWidgets('l\'orologio delle macchie avanza, e col movimento ridotto no', (
    tester,
  ) async {
    ValueListenable<double>? clock;
    Widget app({required bool reduce}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: SpotMotionHost(
        child: Builder(
          builder: (context) {
            clock = SpotMotion.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(app(reduce: false));
    await tester.pump(const Duration(milliseconds: 500));
    final t1 = clock!.value;
    expect(t1, greaterThan(0.3));

    // Col movimento ridotto l'orologio si ferma dov'e'.
    await tester.pumpWidget(app(reduce: true));
    await tester.pump(const Duration(seconds: 1));
    expect(clock!.value, closeTo(t1, 0.05));
  });
}
