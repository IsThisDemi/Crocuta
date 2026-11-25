import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Il timer di spegnimento attivo, se c'e'.
class SleepTimer {
  /// Quando scatta. Nullo se si ferma a fine brano.
  final DateTime? endsAt;

  /// Si ferma alla fine del brano in corso invece che a un'ora precisa.
  final bool endOfTrack;

  const SleepTimer.at(DateTime this.endsAt) : endOfTrack = false;
  const SleepTimer.endOfTrack() : endsAt = null, endOfTrack = true;

  /// Quanto manca, arrotondato per eccesso al minuto: "1 min" fino
  /// all'ultimo secondo, mai "0 min" con la musica ancora accesa.
  int? minutesLeft(DateTime now) {
    final end = endsAt;
    if (end == null) return null;
    final secs = end.difference(now).inSeconds;
    return secs <= 0 ? 0 : (secs + 59) ~/ 60;
  }
}

/// Il timer di spegnimento.
///
/// Due modi, come nelle app che lo hanno: fra N minuti, o alla fine del
/// brano. Il primo abbassa piano prima di fermarsi; il secondo lo fa il
/// player, perche' e' l'unico che sa quando un brano finisce davvero prima
/// che parta il successivo.
class SleepTimerController extends Notifier<SleepTimer?> {
  Timer? _timer;

  @override
  SleepTimer? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void setMinutes(int minutes) {
    _clear();
    final end = DateTime.now().add(Duration(minutes: minutes));
    _timer = Timer(Duration(minutes: minutes), _fire);
    state = SleepTimer.at(end);
  }

  void setEndOfTrack() {
    _clear();
    final player = ref.read(playerProvider.notifier);
    player.pauseAtEndOfTrack = true;
    player.onPausedAtEndOfTrack = () => state = null;
    state = const SleepTimer.endOfTrack();
  }

  void cancel() {
    _clear();
    state = null;
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    final player = ref.read(playerProvider.notifier);
    player.pauseAtEndOfTrack = false;
    player.onPausedAtEndOfTrack = null;
  }

  Future<void> _fire() async {
    _timer = null;
    state = null;
    await ref.read(playerProvider.notifier).fadeOutAndPause();
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimerController, SleepTimer?>(
  SleepTimerController.new,
);
