import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeen_music/design/accent.dart';
import 'package:yeen_music/design/app_theme.dart';

const _red = Color(0xFFE0604A);

/// Cambiando brano, finche' la copertina nuova non e' letta, il colore
/// resta quello di prima: niente lampo del viola di marca.
void main() {
  testWidgets('la copertina nuova che carica tiene il colore di prima', (
    tester,
  ) async {
    final never = Completer<Color>();
    final url = ValueNotifier('a');
    Color? seen;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artworkAccentProvider('a').overrideWith((ref) async => _red),
          artworkAccentProvider('b').overrideWith((ref) => never.future),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: url,
            builder: (_, u, _) => AccentScope(
              artworkUrl: u,
              child: Builder(
                builder: (context) {
                  seen = context.colors.accent;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen, _red);

    url.value = 'b';
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(seen, _red);
    expect(seen, isNot(AppColors.irisBright));
  });
}
