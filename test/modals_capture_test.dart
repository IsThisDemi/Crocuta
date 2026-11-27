import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/tokens.dart';
import 'package:crocuta/widgets/glass_surfaces.dart';

import 'support/capture.dart';

/// Contenuto finto dietro la superficie modale.
///
/// Serve a qualcosa: una superficie traslucida su fondo nero piatto sembra
/// corretta anche quando non lo e'. Righe di testo e blocchi colorati dietro
/// rendono visibile se il vetro separa davvero il modale dal contenuto.
class _Host extends StatelessWidget {
  final void Function(BuildContext ctx) open;

  const _Host({required this.open});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink900,
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            itemCount: 20,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        AppColors.iris,
                        AppColors.coral,
                        i / 20,
                      ),
                      borderRadius: AppRadius.br(AppRadius.xs),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Brano di prova con un titolo lungo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: Builder(
              builder: (ctx) => FilledButton(
                key: const ValueKey('open'),
                onPressed: () => open(ctx),
                child: const Text('Apri'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _tapOpen(WidgetTester tester) =>
    tester.tap(find.byKey(const ValueKey('open')));

void main() {
  testWidgets('cattura: alert di vetro, anche su una finestra larga', (
    tester,
  ) async {
    for (final (name, size) in [
      ('glass_dialog', const Size(430, 932)),
      // Il caso della segnalazione: sul Mac il dialog si stirava per tutta
      // la finestra.
      ('glass_dialog_mac', const Size(1400, 900)),
    ]) {
      await capture(
        tester,
        _Host(
          open: (ctx) => showGlassTextPrompt(
            context: ctx,
            title: 'New Playlist',
            message: 'Enter a name for this playlist.',
            hint: 'Title',
            confirmLabel: 'Create',
          ),
        ),
        name: name,
        size: size,
        interact: _tapOpen,
      );
      final alert = tester.getRect(find.text('New Playlist'));
      expect(alert.center.dx, closeTo(size.width / 2, 1));
      // Largo come un alert di iOS, non come la finestra.
      final field = tester.getRect(find.byType(TextField));
      expect(field.width, lessThan(300));
    }
  });

  testWidgets('il nome: Create spento finche\' e\' vuoto, poi il testo pulito', (
    tester,
  ) async {
    String? result = 'mai chiamato';
    await capture(
      tester,
      _Host(
        open: (ctx) async => result = await showGlassTextPrompt(
          context: ctx,
          title: 'New Playlist',
          confirmLabel: 'Create',
        ),
      ),
      name: 'glass_dialog_vuoto',
      interact: _tapOpen,
    );
    // Vuoto: premere Create non chiude niente.
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('New Playlist'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Notturno  ');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('New Playlist'), findsNothing);
    expect(result, 'Notturno');
  });

  testWidgets('Cancel restituisce null, la conferma distruttiva true', (
    tester,
  ) async {
    String? name = 'mai chiamato';
    bool? deleted;
    await capture(
      tester,
      _Host(
        open: (ctx) async {
          name = await showGlassTextPrompt(
            context: ctx,
            title: 'Rename Playlist',
            initial: 'Vecchio',
            confirmLabel: 'Save',
          );
          if (!ctx.mounted) return;
          deleted = await showGlassConfirm(
            context: ctx,
            title: 'Delete "Vecchio"?',
            confirmLabel: 'Delete',
            destructive: true,
          );
        },
      ),
      name: 'glass_confirm',
      interact: _tapOpen,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(name, isNull);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('cattura: sheet di vetro', (tester) async {
    await capture(
      tester,
      _Host(
        open: (ctx) => showGlassSheet<void>(
          context: ctx,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ListTile(
                leading: Icon(Icons.playlist_play_rounded),
                title: Text('Riproduci dopo'),
              ),
              ListTile(
                leading: Icon(Icons.queue_music_rounded),
                title: Text('Aggiungi alla coda'),
              ),
              ListTile(
                leading: Icon(Icons.favorite_border_rounded),
                title: Text('Aggiungi ai preferiti'),
              ),
              ListTile(
                leading: Icon(Icons.person_rounded),
                title: Text("Vai all'artista"),
              ),
            ],
          ),
        ),
      ),
      name: 'glass_sheet',
      interact: _tapOpen,
    );
  });

  testWidgets('cattura: menu di vetro al puntatore', (tester) async {
    await capture(
      tester,
      _Host(
        open: (ctx) => showGlassMenu<int>(
          context: ctx,
          globalPosition: const Offset(120, 300),
          items: const [
            GlassMenuItem(
              value: 0,
              icon: Icons.play_arrow_rounded,
              label: 'Riproduci dopo',
            ),
            GlassMenuItem(
              value: 1,
              icon: Icons.queue_music_rounded,
              label: 'Aggiungi alla coda',
            ),
            GlassMenuItem(
              value: 2,
              icon: Icons.album_rounded,
              label: "Vai all'album",
              enabled: false,
            ),
            GlassMenuItem(
              value: 3,
              icon: Icons.delete_outline_rounded,
              label: 'Rimuovi dalla coda',
              isDestructive: true,
            ),
          ],
        ),
      ),
      name: 'glass_menu',
      interact: _tapOpen,
    );
  });

  testWidgets('cattura: menu ancorato al bordo destro', (tester) async {
    await capture(
      tester,
      _Host(
        // Volutamente fuori schermo a destra: il delegate deve riportarlo
        // dentro invece di tagliarlo.
        open: (ctx) => showGlassMenu<int>(
          context: ctx,
          globalPosition: const Offset(410, 880),
          items: const [
            GlassMenuItem(
              value: 0,
              icon: Icons.edit_rounded,
              label: 'Rinomina',
            ),
            GlassMenuItem(
              value: 1,
              icon: Icons.delete_outline_rounded,
              label: 'Elimina',
              isDestructive: true,
            ),
          ],
        ),
      ),
      name: 'glass_menu_bordo',
      interact: _tapOpen,
    );
  });
}
