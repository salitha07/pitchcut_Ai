import 'dart:async';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
          return 'Camera permission denied. '
              'Allow camera access and retry.';

        case 'CameraAccessDeniedWithoutPrompt':
          return 'Camera permission blocked. '
              'Enable it in device settings.';

        case 'CameraAccessRestricted':
          return 'Camera access is restricted '
              'on this device.';

        case 'AudioAccessDenied':
          return 'Microphone permission denied. '
              'Allow microphone access.';

        case 'AudioAccessDeniedWithoutPrompt':
          return 'Microphone permission blocked. '
              'Enable it in device settings.';

        case 'AudioAccessRestricted':
          return 'Microphone access is restricted '
              'on this device.';

        default:
          return 'Camera error: '
              '${error.description ?? error.code}';
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

      // Sensor failure must not stop video recording.
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

      // If the app moved to the background while
      // starting a recording, handle it now.
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

      // Attempt to finalize the recording.
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
      // Always stop motion sensor tracking.
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
      // Defer video-player initialization until
      // the Android app returns to the foreground.
      _pendingInterruptedVideo = video;
    } else {
      try {
        await _prepareVideoPreview(video);

        if (mounted && interrupted) {
          setState(() {
            _error =
                'Recording stopped when the app went '
                'into the background. Review and save '
                'the video.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error =
                'Video captured, but preview '
                'could not open: $e';
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
          content: Text(
            'Permanent project saving '
            'currently requires Android.',
          ),
        ),
      );
      return;
    }

    final video = _selectedVideo!;
    final player = _videoController;

    if (player == null || !player.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video preview or metadata '
            'is not ready.',
          ),
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
            content: Text(
              'Project "${project.title}" '
              'saved successfully!',
            ),
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
    // Wait for camera initialization before disposing.
    await _cameraInitialization;

    if (!mounted) return;

    // An operation may still be starting or stopping.
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
    // Wait for any active background operation.
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
                'Recording stopped because the app '
                'entered the background. '
                'Review and save it.';
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Video captured, but '
                'preview failed: $e';
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
      return const Center(child: Text('Video preview unavailable'));
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
          onPressed: _savingProject ? null : _togglePlayback,
          icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
          label: Text(player.value.isPlaying ? 'Pause Video' : 'Play Video'),
        ),
      ],
    );
  }

  // ==========================================
  // CAMERA PREVIEW + FACE FRAMING
  // ==========================================

  Widget _buildCameraPreview(CameraController camera) {
    return Center(
      child: AspectRatio(
        aspectRatio: camera.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(camera),

            if (_showFramingGuide) const Positioned.fill(child: FramingGuide()),

            if (_isCountingDown)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(
                    child: Text(
                      '$_countdownRemaining',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 90,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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

        const SizedBox(height: 8),

        if (_isRecording)
          Text(
            'REC ${_formatDuration(_recordingDuration)}',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

        if (_isCountingDown)
          Text(
            'Recording starts in '
            '$_countdownRemaining...',
          ),

        const SizedBox(height: 8),

        if (!_isRecording && !_isCountingDown)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Countdown: '),

              DropdownButton<int>(
                value: _selectedCountdown,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Off')),
                  DropdownMenuItem(value: 3, child: Text('3s')),
                  DropdownMenuItem(value: 5, child: Text('5s')),
                  DropdownMenuItem(value: 10, child: Text('10s')),
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

        if (!_isRecording && !_isCountingDown)
          SwitchListTile(
            dense: true,
            title: const Text('Face Framing Guide'),
            value: _showFramingGuide,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _showFramingGuide = value;
                    });
                  },
          ),

        const SizedBox(height: 8),

        if (_busy)
          const CircularProgressIndicator()
        else if (_isCountingDown)
          ElevatedButton.icon(
            onPressed: _cancelCountdown,
            icon: const Icon(Icons.close),
            label: const Text('Cancel Countdown'),
          )
        else
          ElevatedButton.icon(
            onPressed: _isRecording ? _stopRecording : _startCountdown,
            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
          ),

        const SizedBox(height: 8),

        ElevatedButton.icon(
          onPressed: (_busy || _loading || _isRecording || _isCountingDown)
              ? null
              : _importVideo,
          icon: const Icon(Icons.video_library),
          label: const Text('Import Video'),
        ),

        const SizedBox(height: 8),

        ElevatedButton.icon(
          onPressed:
              (_cameras.length > 1 &&
                  !_isRecording &&
                  !_isCountingDown &&
                  !_busy)
              ? _switchCamera
              : null,
          icon: const Icon(Icons.cameraswitch),
          label: const Text('Switch Camera'),
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

                    if (!_isRecording &&
                        !_isCountingDown &&
                        !_busy &&
                        !hasVideo)
                      TextButton(
                        onPressed: _initializeCamera,
                        child: const Text('Try Again'),
                      ),
                  ],
                ),
              ),

            Expanded(
              child: _loading && !hasVideo
                  ? const Center(child: CircularProgressIndicator())
                  : hasVideo
                  ? _buildVideoPreview()
                  : camera != null && camera.value.isInitialized
                  ? _buildCameraView(camera)
                  : const Center(child: Text('Camera unavailable')),
            ),

            if (hasVideo)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isImportedVideo)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Imported video'),
                      ),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_savingProject || _busy)
                            ? null
                            : _saveProject,
                        icon: _savingProject
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _savingProject ? 'Saving Project...' : 'Save Project',
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (_busy || _savingProject)
                            ? null
                            : _backToCamera,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back to Camera'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
