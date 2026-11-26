import 'dart:async';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'services/capture_project_service.dart';
import 'services/sensor_logging_service.dart';
import 'widgets/framing_guide.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final CaptureProjectService _captureProjectService = CaptureProjectService();
  final SensorLoggingService _sensorService = SensorLoggingService();

  CameraController? _controller;
  VideoPlayerController? _videoController;

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  bool _loading = true;
  bool _busy = false;
  bool _savingProject = false;
  bool _isRecording = false;
  bool _isCountingDown = false;
  bool _showFramingGuide = true;
  bool _isImportedVideo = false;
  bool _appInBackground = false;

  Future<void>? _cameraInitialization;
  Future<void>? _backgroundTask;
  Future<void>? _resumeTask;

  XFile? _pendingInterruptedVideo;
  XFile? _selectedVideo;
  String? _error;

  int _selectedCountdown = 3;
  int _countdownRemaining = 0;
  int _countdownToken = 0;

  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;

  // ==========================================
  // THEME COLORS
  // ==========================================

  static const Color _backgroundColor = Color(0xFF10111D);
  static const Color _surfaceColor = Color(0xFF1B1D2D);
  static const Color _cardColor = Color(0xFF24263A);
  static const Color _accentColor = Color(0xFF8B7CFF);
  static const Color _recordColor = Color(0xFFFF5364);
  static const Color _successColor = Color(0xFF43D9A3);
  static const Color _textColor = Color(0xFFF5F5FA);
  static const Color _mutedColor = Color(0xFF9A9CAF);

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // ==========================================
  // INITIALIZATION
  // ==========================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  // ==========================================
  // CAMERA PERMISSION ERROR HANDLING
  // ==========================================

  String _cameraErrorMessage(Object error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'CameraAccessDenied':
          return 'Camera permission denied. Allow camera access and retry.';

        case 'CameraAccessDeniedWithoutPrompt':
          return 'Camera permission blocked. Enable it in device settings.';

        case 'CameraAccessRestricted':
          return 'Camera access is restricted on this device.';

        case 'AudioAccessDenied':
          return 'Microphone permission denied. Allow microphone access.';

        case 'AudioAccessDeniedWithoutPrompt':
          return 'Microphone permission blocked. Enable it in device settings.';

        case 'AudioAccessRestricted':
          return 'Microphone access is restricted on this device.';

        default:
          return 'Camera error: ${error.description ?? error.code}';
      }
    }

    return 'Unable to access camera: $error';
  }

  // ==========================================
  // VIDEO RECORDING ERROR HANDLING
  // ==========================================

  String _recordingErrorMessage(Object error) {
    if (error is CameraException) {
      return _cameraErrorMessage(error);
    }

    return 'Video recording failed: $error';
  }

  // ==========================================
  // CAMERA INITIALIZATION
  // ==========================================

  Future<void> _initializeCamera() async {
    if (!mounted ||
        _appInBackground ||
        _busy ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _selectedVideo != null) {
      return;
    }

    final existing = _cameraInitialization;

    if (existing != null) {
      await existing;
      return;
    }

    final task = _initializeCameraInternal();
    _cameraInitialization = task;

    try {
      await task;
    } finally {
      if (identical(_cameraInitialization, task)) {
        _cameraInitialization = null;
      }
    }
  }

  Future<void> _initializeCameraInternal() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw StateError('No cameras were found.');
      }

      if (!mounted || _appInBackground) return;

      _cameras = cameras;

      await _openCamera(_cameraIndex % cameras.length);
    } catch (e) {
      if (!mounted || _appInBackground) return;

      setState(() {
        _loading = false;
        _error = _cameraErrorMessage(e);
      });
    }
  }

  Future<void> _openCamera(int index) async {
    final oldCamera = _controller;
    _controller = null;

    await oldCamera?.dispose();

    if (!mounted || _appInBackground) return;

    final camera = CameraController(
      _cameras[index],
      ResolutionPreset.low,
      enableAudio: true,
    );

    try {
      await camera.initialize();

      if (!mounted || _appInBackground) {
        await camera.dispose();
        return;
      }

      setState(() {
        _controller = camera;
        _cameraIndex = index;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      await camera.dispose();
      rethrow;
    }
  }

  // ==========================================
  // SWITCH CAMERA
  // ==========================================

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _loading ||
        _busy ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _appInBackground ||
        _selectedVideo != null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final next = (_cameraIndex + 1) % _cameras.length;

      await _openCamera(next);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _cameraErrorMessage(e);
      });
    }
  }

  // ==========================================
  // COUNTDOWN TIMER
  // ==========================================

  Future<void> _startCountdown() async {
    if (_busy ||
        _loading ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _appInBackground ||
        _selectedVideo != null ||
        _controller?.value.isInitialized != true) {
      return;
    }

    if (_selectedCountdown == 0) {
      await _startRecording();
      return;
    }

    final token = ++_countdownToken;

    setState(() {
      _isCountingDown = true;
      _countdownRemaining = _selectedCountdown;
      _error = null;
    });

    while (_countdownRemaining > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));

      if (!mounted ||
          _appInBackground ||
          token != _countdownToken ||
          !_isCountingDown) {
        return;
      }

      setState(() {
        _countdownRemaining--;
      });
    }

    if (!mounted || _appInBackground || token != _countdownToken) {
      return;
    }

    setState(() {
      _isCountingDown = false;
    });

    await _startRecording();
  }

  void _cancelCountdown() {
    _countdownToken++;

    if (mounted) {
      setState(() {
        _isCountingDown = false;
        _countdownRemaining = 0;
      });
    }
  }

  // ==========================================
  // RECORDING DURATION TIMER
  // ==========================================

  void _startTimer() {
    _timer?.cancel();

    _stopwatch
      ..reset()
      ..start();

    _recordingDuration = Duration.zero;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _recordingDuration = _stopwatch.elapsed;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;

    _stopwatch.stop();
    _recordingDuration = _stopwatch.elapsed;
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');

    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  // ==========================================
  // VIDEO PREVIEW
  // ==========================================

  Future<void> _prepareVideoPreview(XFile video) async {
    final VideoPlayerController player;

    if (kIsWeb) {
      player = VideoPlayerController.networkUrl(Uri.parse(video.path));
    } else {
      player = VideoPlayerController.file(File(video.path));
    }

    try {
      await player.initialize();
      await player.setLooping(true);

      if (!mounted) {
        await player.dispose();
        return;
      }

      final previous = _videoController;
      _videoController = player;

      await previous?.dispose();

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  Future<void> _clearSelectedVideo() async {
    final previous = _videoController;

    _videoController = null;
    _selectedVideo = null;
    _pendingInterruptedVideo = null;
    _isImportedVideo = false;

    await previous?.dispose();
  }

  // ==========================================
  // PLAY / PAUSE VIDEO
  // ==========================================

  Future<void> _togglePlayback() async {
    final player = _videoController;

    if (player == null || !player.value.isInitialized) {
      return;
    }

    try {
      if (player.value.isPlaying) {
        await player.pause();
      } else {
        await player.play();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Playback error: $e';
        });
      }
    }
  }

  // ==========================================
  // GALLERY VIDEO IMPORT
  // ==========================================

  Future<void> _importVideo() async {
    if (_busy ||
        _loading ||
        _savingProject ||
        _isRecording ||
        _isCountingDown) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);

      if (video == null || !mounted) {
        return;
      }

      await _clearSelectedVideo();
      await _prepareVideoPreview(video);

      if (!mounted) return;

      setState(() {
        _selectedVideo = video;
        _isImportedVideo = true;
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to import video: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }

      if (_isAndroid && _appInBackground) {
        unawaited(_handleBackground());
      }
    }
  }

  // ==========================================
  // START VIDEO RECORDING + SENSORS
  // ==========================================

  Future<void> _startRecording() async {
    final camera = _controller;

    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isRecordingVideo ||
        _busy ||
        _loading ||
        _savingProject ||
        _isCountingDown ||
        _appInBackground ||
        _selectedVideo != null) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _clearSelectedVideo();

      await camera.startVideoRecording();

      if (!mounted) {
        await camera.stopVideoRecording();
        return;
      }

      _startTimer();

      try {
        await _sensorService.startRecording();
      } catch (e) {
        debugPrint('Motion sensors unavailable: $e');
      }

      if (!mounted) {
        _stopTimer();

        await _sensorService.stopRecording();

        if (camera.value.isRecordingVideo) {
          await camera.stopVideoRecording();
        }
        return;
      }

      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      _stopTimer();

      try {
        await _sensorService.stopRecording();
      } catch (sensorError) {
        debugPrint('Sensor cleanup error: $sensorError');
      }

      if (mounted) {
        setState(() {
          _isRecording = false;
          _error = _recordingErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }

      if (_isAndroid && _appInBackground) {
        unawaited(_handleBackground());
      }
    }
  }

  // ==========================================
  // FINISH RECORDING / INTERRUPTION RECOVERY
  // ==========================================

  Future<void> _finishRecording({required bool interrupted}) async {
    final camera = _controller;

    if (camera == null || _busy || !_isRecording) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    _stopTimer();

    XFile? video;

    try {
      if (!camera.value.isRecordingVideo) {
        throw StateError('The camera stopped recording unexpectedly.');
      }

      video = await camera.stopVideoRecording();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _selectedVideo = video;
        _isImportedVideo = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _error = interrupted
              ? 'Recording was interrupted. '
                    'The video could not be recovered: $e'
              : _recordingErrorMessage(e);
        });
      }
    } finally {
      try {
        await _sensorService.stopRecording();
      } catch (e) {
        debugPrint('Unable to stop motion sensors: $e');
      }

      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }

    if (video == null || !mounted) return;

    if (_appInBackground) {
      _pendingInterruptedVideo = video;
    } else {
      try {
        await _prepareVideoPreview(video);

        if (mounted && interrupted) {
          setState(() {
            _error =
                'Recording stopped when the app went into '
                'the background. Review and save the video.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Video captured, but preview could not open: $e';
          });
        }
      }
    }
  }

  Future<void> _stopRecording() {
    return _finishRecording(interrupted: false);
  }

  // ==========================================
  // SAVE PROJECT + SENSOR DATA
  // ==========================================

  Future<void> _saveProject() async {
    if (_savingProject ||
        _busy ||
        _isRecording ||
        _isCountingDown ||
        _appInBackground ||
        _selectedVideo == null) {
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permanent project saving currently requires Android.'),
        ),
      );
      return;
    }

    final video = _selectedVideo!;
    final player = _videoController;

    if (player == null || !player.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video preview or metadata is not ready.'),
        ),
      );
      return;
    }

    final titleController = TextEditingController(
      text:
          'PitchCut Video '
          '${DateTime.now().millisecondsSinceEpoch}',
    );

    String? title;

    try {
      title = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Save New Project'),
            content: TextField(
              controller: titleController,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Project Title',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = titleController.text.trim();

                  if (name.isNotEmpty) {
                    Navigator.of(dialogContext).pop(name);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => titleController.dispose(),
      );
    }

    if (!mounted || title == null || title.trim().isEmpty) {
      return;
    }

    final size = player.value.size;

    final durationMs = player.value.duration.inMilliseconds;

    final width = size.width.round();
    final height = size.height.round();

    if (durationMs <= 0 || width <= 0 || height <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid video metadata.')));
      return;
    }

    setState(() {
      _savingProject = true;
    });

    try {
      final project = await _captureProjectService.saveAsNewProject(
        video: video,
        title: title,
        durationMs: durationMs,
        width: width,
        height: height,
        sensorService: _sensorService,
        isImportedVideo: _isImportedVideo,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Project "${project.title}" saved successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to save project: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingProject = false;
        });
      }
    }
  }

  // ==========================================
  // BACK TO CAMERA
  // ==========================================

  Future<void> _backToCamera() async {
    if (_busy ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _appInBackground) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _loading = true;
    });

    try {
      await _clearSelectedVideo();

      if (!mounted) return;

      _recordingDuration = Duration.zero;
      _stopwatch.reset();

      final oldCamera = _controller;
      _controller = null;

      await oldCamera?.dispose();

      if (!mounted) return;

      setState(() {
        _busy = false;
      });

      await _initializeCamera();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
          _error = 'Unable to reopen camera: $e';
        });
      }
    }
  }

  // ==========================================
  // ANDROID APP LIFECYCLE
  // ==========================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroid) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appInBackground = true;

        if (_isCountingDown) {
          _cancelCountdown();
        }

        unawaited(_handleBackground());
        break;

      case AppLifecycleState.resumed:
        _appInBackground = false;

        unawaited(_handleResume());
        break;

      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _handleBackground() async {
    final existing = _backgroundTask;

    if (existing != null) {
      return existing;
    }

    final task = _handleBackgroundInternal();
    _backgroundTask = task;

    try {
      await task;
    } finally {
      if (identical(_backgroundTask, task)) {
        _backgroundTask = null;
      }
    }
  }

  Future<void> _handleBackgroundInternal() async {
    await _cameraInitialization;

    if (!mounted) return;

    if (_busy || _savingProject) return;

    if (_isRecording) {
      await _finishRecording(interrupted: true);
    }

    if (!mounted || _busy || _savingProject) {
      return;
    }

    final camera = _controller;
    _controller = null;

    try {
      await camera?.dispose();
    } catch (e) {
      debugPrint('Background camera dispose failed: $e');
    }

    if (mounted) {
      setState(() {
        _loading = _selectedVideo == null;
      });
    }
  }

  // ==========================================
  // RESTORE AFTER APP RESUMES
  // ==========================================

  Future<void> _handleResume() async {
    final existing = _resumeTask;

    if (existing != null) {
      return existing;
    }

    final task = _handleResumeInternal();
    _resumeTask = task;

    try {
      await task;
    } finally {
      if (identical(_resumeTask, task)) {
        _resumeTask = null;
      }
    }
  }

  Future<void> _handleResumeInternal() async {
    await _backgroundTask;

    if (!mounted ||
        _appInBackground ||
        _busy ||
        _savingProject ||
        _isRecording) {
      return;
    }

    final pending = _pendingInterruptedVideo;

    if (pending != null) {
      _pendingInterruptedVideo = null;

      try {
        await _prepareVideoPreview(pending);

        if (mounted) {
          setState(() {
            _error =
                'Recording stopped because the app entered '
                'the background. Review and save it.';
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Video captured, but preview failed: $e';
          });
        }
      }

      return;
    }

    if (_selectedVideo != null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    if (_controller?.value.isInitialized == true) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    await _initializeCamera();
  }

  // ==========================================
  // DISPOSE
  // ==========================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _countdownToken++;
    _stopTimer();

    unawaited(_sensorService.dispose());

    _controller?.dispose();
    _videoController?.dispose();

    super.dispose();
  }

  // ==========================================
  // VIDEO PREVIEW UI
  // ==========================================

  Widget _buildVideoPreview() {
    final player = _videoController;

    if (player == null || !player.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: _accentColor),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _cardColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: player.value.aspectRatio,
                  child: VideoPlayer(player),
                ),
                GestureDetector(
                  onTap: _togglePlayback,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      player.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: _statusBadge(
                    _isImportedVideo ? 'IMPORTED VIDEO' : 'RECORDED VIDEO',
                    _successColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Text(
          'Your video is ready!',
          style: TextStyle(
            color: _textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Review your recording before saving it as a project.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _mutedColor, fontSize: 13),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ==========================================
  // CAMERA PREVIEW
  // ==========================================

  Widget _buildCameraPreview(CameraController camera) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = camera.value.previewSize;

        if (previewSize == null ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0) {
          return const Center(
            child: CircularProgressIndicator(color: _accentColor),
          );
        }

        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;

        final previewWidth = isPortrait
            ? previewSize.height
            : previewSize.width;

        final previewHeight = isPortrait
            ? previewSize.width
            : previewSize.height;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: CameraPreview(camera),
                  ),
                ),
              ),

              if (_showFramingGuide)
                const Positioned.fill(
                  child: IgnorePointer(child: FramingGuide()),
                ),

              // Camera status
              Positioned(
                top: 14,
                left: 14,
                child: _statusBadge(
                  _isRecording ? 'RECORDING' : 'CAMERA READY',
                  _isRecording ? _recordColor : _successColor,
                ),
              ),

              // Recording timer
              if (_isRecording)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: _recordColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _formatDuration(_recordingDuration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Countdown overlay
              if (_isCountingDown)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Center(
                      child: Text(
                        '$_countdownRemaining',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 100,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

              // Framing information
              if (_showFramingGuide && !_isRecording && !_isCountingDown)
                Positioned(
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.center_focus_strong_rounded,
                          color: _successColor,
                          size: 16,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Position yourself in the frame',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // STATUS BADGE
  // ==========================================

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CAMERA OPTION BUTTON
  // ==========================================

  Widget _cameraOption({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              Icon(icon, color: enabled ? _textColor : _mutedColor, size: 23),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? _textColor : _mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // CAMERA CONTROLS
  // ==========================================

  Widget _buildCameraView(CameraController camera) {
    return Column(
      children: [
        Expanded(child: _buildCameraPreview(camera)),

        const SizedBox(height: 16),

        // Countdown selector
        if (!_isRecording && !_isCountingDown) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: _accentColor, size: 21),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Countdown',
                    style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DropdownButton<int>(
                  value: _selectedCountdown,
                  dropdownColor: _cardColor,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.bold,
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Off')),
                    DropdownMenuItem(value: 3, child: Text('3 sec')),
                    DropdownMenuItem(value: 5, child: Text('5 sec')),
                    DropdownMenuItem(value: 10, child: Text('10 sec')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _selectedCountdown = value;
                            });
                          }
                        },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Face framing switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.face, color: _accentColor),
              title: const Text(
                'Face Framing Guide',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Keep yourself properly positioned',
                style: TextStyle(color: _mutedColor, fontSize: 11),
              ),
              value: _showFramingGuide,
              activeThumbColor: _accentColor,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() {
                        _showFramingGuide = value;
                      });
                    },
            ),
          ),
        ],

        // Recording status
        if (_isRecording) ...[
          const SizedBox(height: 8),
          const Text(
            'Recording in progress',
            style: TextStyle(
              color: _recordColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],

        if (_isCountingDown) ...[
          const SizedBox(height: 8),
          Text(
            'Recording starts in $_countdownRemaining seconds',
            style: const TextStyle(
              color: _accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Main recording button
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: _accentColor),
          )
        else if (_isCountingDown)
          OutlinedButton.icon(
            onPressed: _cancelCountdown,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel Countdown'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _textColor,
              side: const BorderSide(color: _recordColor),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )
        else
          GestureDetector(
            onTap: _isRecording ? _stopRecording : _startCountdown,
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isRecording ? _recordColor : Colors.white,
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isRecording ? 29 : 58,
                      height: _isRecording ? 29 : 58,
                      decoration: BoxDecoration(
                        color: _recordColor,
                        borderRadius: BorderRadius.circular(
                          _isRecording ? 8 : 50,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRecording ? 'STOP RECORDING' : 'START RECORDING',
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 18),

        // Gallery and camera switching
        Row(
          children: [
            _cameraOption(
              icon: Icons.video_library_rounded,
              label: 'Gallery',
              onTap: (_busy || _loading || _isRecording || _isCountingDown)
                  ? null
                  : _importVideo,
            ),
            const SizedBox(width: 12),
            _cameraOption(
              icon: Icons.cameraswitch_rounded,
              label: 'Flip Camera',
              onTap:
                  (_cameras.length > 1 &&
                      !_busy &&
                      !_loading &&
                      !_isRecording &&
                      !_isCountingDown)
                  ? _switchCamera
                  : null,
            ),
          ],
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  // ==========================================
  // MAIN UI
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final camera = _controller;
    final hasVideo = _selectedVideo != null;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        elevation: 0,
        centerTitle: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PitchCut AI',
              style: TextStyle(
                color: _textColor,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'VIDEO STUDIO',
              style: TextStyle(
                color: _mutedColor,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.videocam_rounded, color: _accentColor),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page heading
              if (!hasVideo) ...[
                const Text(
                  'Create your moment',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Get ready and record your presentation.',
                  style: TextStyle(color: _mutedColor, fontSize: 12),
                ),
                const SizedBox(height: 16),
              ],

              // Error message
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _recordColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _recordColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: _recordColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (!_isRecording &&
                          !_isCountingDown &&
                          !_busy &&
                          !hasVideo)
                        IconButton(
                          onPressed: _initializeCamera,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: _accentColor,
                          ),
                        ),
                    ],
                  ),
                ),

              // Main content
              Expanded(
                child: _loading && !hasVideo
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: _accentColor),
                            SizedBox(height: 16),
                            Text(
                              'Preparing your camera...',
                              style: TextStyle(color: _mutedColor),
                            ),
                          ],
                        ),
                      )
                    : hasVideo
                    ? _buildVideoPreview()
                    : camera != null && camera.value.isInitialized
                    ? _buildCameraView(camera)
                    : const Center(
                        child: Text(
                          'Camera unavailable',
                          style: TextStyle(color: _mutedColor),
                        ),
                      ),
              ),

              // Video actions
              if (hasVideo) ...[
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: (_savingProject || _busy) ? null : _saveProject,
                    icon: _savingProject
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _savingProject ? 'Saving Project...' : 'Save as Project',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: (_busy || _savingProject) ? null : _backToCamera,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back to Camera'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textColor,
                      side: const BorderSide(color: _cardColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
