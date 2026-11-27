import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/spot.dart';
import 'package:crocuta/design/text_pulse.dart';

/// I testi che pulsano: crescono sui colpi solo se accesi, e accenderli o
/// spegnerli non ricrea cio' che sta sotto.
void main() {
  Widget app(ValueNotifier<SpotMusic> music, bool on, Key key) => MaterialApp(
    home: SpotMotion(
      time: ValueNotifier(0),
      music: music,
      child: TextPulse(
        enabled: on,
        child: _Probe(key: key),
      ),
    ),
  );

  testWidgets('cresce sul colpo, solo se acceso', (tester) async {
    final music = ValueNotifier<SpotMusic>(silentMusic);
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(app(music, true, key));
    expect(key.currentState!.scale, 1);
    music.value = (pulse: 1, snap: 0, energy: 0);
    await tester.pump();
    expect(key.currentState!.scale, closeTo(1 + TextPulse.bass, 0.006));

    final first = key.currentState;
    await tester.pumpWidget(app(music, false, key));
    expect(key.currentState!.scale, 1);
    // Lo stesso stato: spegnerlo non ha ricreato la pagina.
    expect(identical(key.currentState, first), isTrue);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  double scale = 0;

  @override
  Widget build(BuildContext context) {
    scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return const Text('ciao');
  }
}
