import 'package:yeen_music/services/player_controller.dart';
import 'package:yeen_music/services/player_state.dart';

/// A player that returns a canned state without opening libmpv or touching
/// the network, so widgets that depend on playback can be rendered in a
/// plain widget test.
class FakePlayer extends PlayerController {
  FakePlayer([this._state = const PlayerState()]);

  final PlayerState _state;

  @override
  PlayerState build() => _state;
}
