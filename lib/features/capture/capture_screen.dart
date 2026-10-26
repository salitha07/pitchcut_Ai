import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  VideoPlayerController? _videoController;

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  bool _loading = true;
  bool _busy = false;
  bool _isRecording = false;

  String? _error;
  XFile? _recordedVideo;

  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        throw Exception('No camera found on this device.');
      }

      await _openCamera(_cameraIndex % _cameras.length);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = _cameraErrorMessage(e);
        _loading = false;
      });
    }
  }

  String _cameraErrorMessage(Object error) {
    if (error is CameraException) {
      final code = error.code.toLowerCase();

      if (code.contains('denied') ||
          code.contains('permission') ||
          code.contains('notallowed')) {
        return 'Camera or microphone permission denied. '
            'Allow access in your browser settings and try again.';
      }

      return 'Camera error: ${error.description ?? error.code}';
    }

    return 'Camera error: $error';
  }

  Future<void> _openCamera(int index) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final controller = CameraController(
      _cameras[index],

      // OPTIMIZATION 1:
      // Lower camera resolution for smoother Chrome testing.
      ResolutionPreset.low,

      enableAudio: true,
    );

    try {
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _loading ||
        _busy ||
        _isRecording ||
        _recordedVideo != null) {
      return;
    }

    setState(() => _loading = true);

    try {
      final next = (_cameraIndex + 1) % _cameras.length;
      await _openCamera(next);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = _cameraErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();

    _stopwatch
      ..reset()
      ..start();

    _recordingDuration = Duration.zero;

    // OPTIMIZATION 2:
    // Update the recording timer once per second.
    // This reduces unnecessary widget rebuilds.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        _recordingDuration = _stopwatch.elapsed;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    _recordingDuration = _stopwatch.elapsed;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isRecordingVideo ||
        _busy ||
        _loading) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _clearRecordedVideo();
      await controller.startVideoRecording();

      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _busy = false;
      });

      _startTimer();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to start recording: $e';
        _busy = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;

    if (controller == null || !controller.value.isRecordingVideo || _busy) {
      return;
    }

    setState(() => _busy = true);

    _stopTimer();

    try {
      final video = await controller.stopVideoRecording();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _recordedVideo = video;
      });

      // Web recordings usually use a browser blob URL.
      // Android local-file playback will be added later.
      if (kIsWeb) {
        final player = VideoPlayerController.networkUrl(Uri.parse(video.path));

        await player.initialize();

        if (!mounted) {
          await player.dispose();
          return;
        }

        await player.setLooping(true);

        _videoController = player;

        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _error = 'Unable to stop or preview recording: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearRecordedVideo() async {
    final previous = _videoController;
    _videoController = null;
    _recordedVideo = null;

    if (previous != null) {
      await previous.dispose();
    }
  }

  Future<void> _recordAgain() async {
    if (_busy) return;

    setState(() => _busy = true);

    await _clearRecordedVideo();

    if (!mounted) return;

    setState(() {
      _recordingDuration = Duration.zero;
      _busy = false;
      _error = null;
    });
  }

  Future<void> _togglePlayback() async {
    final player = _videoController;

    if (player == null || !player.value.isInitialized) return;

    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }

    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android camera lifecycle handling will be
    // implemented and tested on a real Android device.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _stopTimer();
    _stopwatch.stop();

    _controller?.dispose();
    _videoController?.dispose();

    super.dispose();
  }

  Widget _buildVideoPreview() {
    final player = _videoController;

    if (player == null || !player.value.isInitialized) {
      return const Center(
        child: Text(
          'Video recorded. Android preview will be added later.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: player.value.aspectRatio,
              child: VideoPlayer(player),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _togglePlayback,
          icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
          label: Text(player.value.isPlaying ? 'Pause Video' : 'Play Video'),
        ),
      ],
    );
  }

  Widget _buildCameraView(CameraController controller) {
    return Column(
      children: [
        Expanded(child: Center(child: CameraPreview(controller))),
        const SizedBox(height: 12),

        if (_isRecording)
          Text(
            'REC  ${_formatDuration(_recordingDuration)}',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

        const SizedBox(height: 12),

        if (_busy)
          const CircularProgressIndicator()
        else
          ElevatedButton.icon(
            onPressed: _isRecording ? _stopRecording : _startRecording,
            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
          ),

        const SizedBox(height: 8),

        ElevatedButton.icon(
          onPressed: (_cameras.length > 1 && !_isRecording && !_busy)
              ? _switchCamera
              : null,
          icon: const Icon(Icons.cameraswitch),
          label: const Text('Switch Camera'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final hasVideo = _recordedVideo != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Record Video')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    if (!_isRecording && !_busy && !hasVideo)
                      TextButton(
                        onPressed: _initializeCamera,
                        child: const Text('Try Again'),
                      ),
                  ],
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : hasVideo
                  ? _buildVideoPreview()
                  : controller != null && controller.value.isInitialized
                  ? _buildCameraView(controller)
                  : const Center(child: Text('Camera unavailable')),
            ),

            if (hasVideo)
              Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _recordAgain,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Record Again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
