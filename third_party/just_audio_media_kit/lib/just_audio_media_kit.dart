/// `package:media_kit` bindings for `just_audio` to support Linux and Windows.
library just_audio_media_kit;

import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:universal_platform/universal_platform.dart';

class JustAudioMediaKit extends JustAudioPlatform {
  JustAudioMediaKit();

  /// The internal MPV player's logLevel
  static MPVLogLevel mpvLogLevel = MPVLogLevel.error;

  /// Sets the demuxer's cache size (in bytes)
  static int bufferSize = 32 * 1024 * 1024;

  /// Sets the name of the underlying window & process for native backend. This is visible inside the Windows' volume mixer.
  static String title = 'JustAudioMediaKit';

  /// Sets the list of allowed protocols for native backend.
  static List<String> protocolWhitelist = const [
    'udp',
    'rtp',
    'tcp',
    'tls',
    'data',
    'file',
    'http',
    'https',
    'crypto',
  ];

  /// Enables or disables pitch shift control for native backend (with this set to false, [setPitch] won't work).
  ///
  /// This uses `scaletempo` under the hood & disables `audio-pitch-correction`.
  static bool pitch = true;

  /// Enables gapless playback via the [`--prefetch-playlist`](https://mpv.io/manual/stable/#options-prefetch-playlist) in libmpv
  ///
  /// This is highly experimental. Use at your own risk.
  ///
  /// Check [mpv's docs](https://mpv.io/manual/stable/#options-prefetch-playlist) and
  /// [the related issue](https://github.com/Pato05/just_audio_media_kit/issues/11) for more information
  static bool prefetchPlaylist = false;

  static final _logger = Logger('JustAudioMediaKit');
  final _players = HashMap<String, MediaKitPlayer>();

  /// Players that are disposing (player id -> future that completes when the player is disposed)
  final _disposingPlayers = HashMap<String, Future<void>>();

  // —— App-side ear-channel routing (AsmrAiPlayer fork) ——
  //
  // just_audio's AudioPlayer does not expose its private `_id`, so we claim
  // roles via an ordered expect-queue: the app calls [expectMainPlayer] /
  // [expectTtsPlayer] immediately before constructing the matching
  // AudioPlayer. The first platform `init` pops `main`, the next pops `tts`.
  // Invariant: the main track always activates first (translation subtitles
  // only appear after main playback has started). `id → role` survives
  // disposePlayer so stop→play re-inits of the same AudioPlayer keep their
  // role and re-apply the stored mpv `af` filter.

  static const String roleMain = 'main';
  static const String roleTts = 'tts';

  static final List<String> _roleQueue = <String>[];
  static final Map<String, String> _idToRole = <String, String>{};
  static final Map<String, MediaKitPlayer> _roleToPlayer =
      <String, MediaKitPlayer>{};
  static String? _mainFilter;
  static String? _ttsFilter;

  /// Queue the next native platform init as the main (or TTS) track.
  static void expectMainPlayer() => _roleQueue.add(roleMain);

  static void expectTtsPlayer() => _roleQueue.add(roleTts);

  /// Store desired mpv `af` for [role] and push it to a live player if any.
  /// [af] `null` clears the stored filter and any live player's `af`.
  static Future<void> setRoleAudioFilter(String role, String? af) async {
    if (role == roleMain) {
      _mainFilter = af;
    } else if (role == roleTts) {
      _ttsFilter = af;
    } else {
      return;
    }
    final player = _roleToPlayer[role];
    if (player != null) {
      await player.setAudioFilter(af ?? '');
    }
  }

  static String? _filterForRole(String role) =>
      role == roleMain ? _mainFilter : _ttsFilter;

  static void _assignRole(String id, MediaKitPlayer player, String role) {
    _idToRole[id] = role;
    _roleToPlayer[role] = player;
    final filter = _filterForRole(role);
    if (filter != null) {
      // Best-effort: a bad af string must not fail player init.
      player.setAudioFilter(filter).ignore();
    }
  }

  /// Initializes the plugin if the platform we're running on is marked
  /// as true, otherwise it will leave everything unchanged.
  ///
  /// Can also be safely called from Web, even though it'll have no effect
  static void ensureInitialized({
    bool linux = true,
    bool windows = true,
    bool android = false,
    bool iOS = false,
    bool macOS = false,

    /// The path to the libmpv dynamic library.
    /// The name of the library is generally `libmpv.so` on GNU/Linux and `libmpv-2.dll` on Windows.
    String? libmpv,
  }) {
    if ((UniversalPlatform.isLinux && linux) ||
        (UniversalPlatform.isWindows && windows) ||
        (UniversalPlatform.isAndroid && android) ||
        (UniversalPlatform.isIOS && iOS) ||
        (UniversalPlatform.isMacOS && macOS)) {
      registerWith();
      MediaKit.ensureInitialized(libmpv: libmpv);
    }
  }

  /// Registers the plugin with [JustAudioPlatform]
  static void registerWith() {
    JustAudioPlatform.instance = JustAudioMediaKit();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_players.containsKey(request.id)) {
      throw PlatformException(
          code: 'error', message: 'Player ${request.id} already exists!');
    }

    _logger.fine('instantiating new player ${request.id}');
    final player = MediaKitPlayer(request.id);
    _players[request.id] = player;

    final knownRole = _idToRole[request.id];
    if (knownRole != null) {
      _roleToPlayer[knownRole] = player;
      final filter = _filterForRole(knownRole);
      if (filter != null) player.setAudioFilter(filter).ignore();
    } else if (_roleQueue.isNotEmpty) {
      _assignRole(request.id, player, _roleQueue.removeAt(0));
    }

    await player.ready();
    _logger.fine('player ready! (players: $_players)');
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    _logger.fine('disposing player ${request.id}');

    // temporary workaround because disposePlayer is called more than once
    if (_disposingPlayers.containsKey(request.id)) {
      _logger.fine('disposePlayer() called more than once!');
      await _disposingPlayers[request.id]!;
      return DisposePlayerResponse();
    }

    if (!_players.containsKey(request.id)) {
      throw PlatformException(
          code: 'error', message: 'Player ${request.id} doesn\'t exist.');
    }

    final role = _idToRole[request.id];
    if (role != null) _roleToPlayer.remove(role);
    // Keep `_idToRole[id]` so stop→play re-init of the same AudioPlayer
    // (same just_audio uuid) restores the role + stored `af` filter.

    final future = _players[request.id]!.release();
    _players.remove(request.id);
    _disposingPlayers[request.id] = future;
    await future;
    _disposingPlayers.remove(request.id);

    _logger.fine('player ${request.id} disposed!');
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    _logger.fine('disposing of all players...');
    if (_players.isNotEmpty) {
      await Future.wait(_players.values.map((e) => e.release()));
      _players.clear();
    }
    _roleToPlayer.clear();
    _roleQueue.clear();
    return DisposeAllPlayersResponse();
  }
}
