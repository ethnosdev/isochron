import 'package:just_audio/just_audio.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get stateStream => _player.playerStateStream;
  Duration? get duration => _player.duration;

  Future<Duration> load(String path) async {
    await _player.setFilePath(path);
    return _player.duration ?? Duration.zero;
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);

  void dispose() => _player.dispose();
}
