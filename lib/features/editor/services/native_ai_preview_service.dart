import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pitchcut_ai/features/editor/models/clip_background.dart';

class NativePreviewState {
  const NativePreviewState({
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
  });

  final int positionMs;
  final int durationMs;
  final bool isPlaying;

  factory NativePreviewState.fromMap(Map<Object?, Object?> map) {
    return NativePreviewState(
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      isPlaying: map['isPlaying'] as bool? ?? false,
    );
  }
}

class NativePreviewSession {
  const NativePreviewSession({
    required this.textureId,
    required this.durationMs,
    required this.positionMs,
    required this.isPlaying,
  });

  final int textureId;
  final int durationMs;
  final int positionMs;
  final bool isPlaying;

  factory NativePreviewSession.fromMap(Map<Object?, Object?> map) {
    final textureId = (map['textureId'] as num?)?.toInt();

    if (textureId == null || textureId < 0) {
      throw const FormatException(
        'Native preview returned an invalid texture ID.',
      );
    }

    return NativePreviewSession(
      textureId: textureId,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      isPlaying: map['isPlaying'] as bool? ?? false,
    );
  }
}

class NativeAiPreviewService {
  static const MethodChannel _methodChannel =
      MethodChannel('pitchcut/editor');

  static const EventChannel _eventChannel =
      EventChannel('pitchcut/editor/preview');

  Stream<NativePreviewState> get states => _eventChannel
      .receiveBroadcastStream()
      .where(
        (event) => event is Map && event['type'] == 'state',
      )
      .map(
        (event) => NativePreviewState.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      )
      .where((state) => state.durationMs >= 0);

  Future<NativePreviewSession> create({
    required String path,
    required ClipBackground background,
  }) async {
    final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'createNativePreview',
      {
        'path': path,
        'background': background.toJson(),
      },
    );

    if (result == null) {
      throw const FormatException(
        'Native preview did not return a session.',
      );
    }

    return NativePreviewSession.fromMap(result);
  }

  Future<void> play() async {
    await _methodChannel.invokeMethod<void>('playNativePreview');
  }

  Future<void> pause() async {
    await _methodChannel.invokeMethod<void>('pauseNativePreview');
  }

  Future<void> seekTo(int positionMs) async {
    await _methodChannel.invokeMethod<void>(
      'seekNativePreview',
      {'positionMs': positionMs < 0 ? 0 : positionMs},
    );
  }

  Future<void> dispose() async {
    await _methodChannel.invokeMethod<void>('disposeNativePreview');
  }
}

