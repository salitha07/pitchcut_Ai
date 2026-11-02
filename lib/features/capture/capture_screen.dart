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
  CameraController? _controller;
  VideoPlayerController? _videoController;

  final ImagePicker _picker = ImagePicker();
  final CaptureProjectService _captureProjectService = CaptureProjectService();
  final SensorLoggingService _sensorService = SensorLoggingService();

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  bool _loading = true;
  bool _busy = false;
  bool _isRecording = false;
  bool _isCountingDown = false;
  bool _showFramingGuide = true;
  bool _savingProject = false;
  bool _isImportedVideo = false;

  // Android lifecycle state
  bool _appInBackground = false;
  Future<void>? _cameraRelease;
  Future<void>? _cameraInitialization;

  String? _error;
  XFile? _selectedVideo;

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
  // CAMERA PERMISSION ERRORS
  // ==========================================

  String _cameraErrorMessage(Object error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'CameraAccessDenied':
          return 'Camera permission denied. '
              'Please allow camera access and try again.';

        case 'CameraAccessDeniedWithoutPrompt':
          return 'Camera permission is blocked. '
              'Enable camera access in device settings.';

        case 'CameraAccessRestricted':
          return 'Camera access is restricted on this device.';

        case 'AudioAccessDenied':
          return 'Microphone permission denied. '
              'Please allow microphone access.';

        case 'AudioAccessDeniedWithoutPrompt':
          return 'Microphone permission is blocked. '
              'Enable microphone access in device settings.';

        case 'AudioAccessRestricted':
          return 'Microphone access is restricted on this device.';

        default:
          return 'Camera error: '
              '${error.description ?? error.code}';
      }
    }

    return 'Unable to access camera: $error';
  }

  // ==========================================
  // RECORDING ERRORS
  // ==========================================

  String _recordingErrorMessage(Object error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'AudioAccessDenied':
          return 'Microphone permission denied. '
              'Allow microphone access and try again.';

        case 'AudioAccessDeniedWithoutPrompt':
          return 'Microphone permission is blocked. '
              'Enable microphone access in device settings.';

        case 'AudioAccessRestricted':
          return 'Microphone access is restricted.';

        case 'CameraAccessDenied':
          return 'Camera permission denied. '
              'Please enable camera access.';

        case 'CameraAccessDeniedWithoutPrompt':
          return 'Camera permission is blocked. '
              'Enable camera access in device settings.';

        case 'CameraAccessRestricted':
          return 'Camera access is restricted.';

        default:
          return 'Video recording failed: '
              '${error.description ?? error.code}';
      }
    }

    return 'Unable to record video: $error';
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

    final existingInitialization = _cameraInitialization;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }

    final future = _initializeCameraInternal();
    _cameraInitialization = future;

    try {
      await future;
    } finally {
      _cameraInitialization = null;
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
        throw StateError('No camera found on this device.');
      }

      if (!mounted || _appInBackground) return;

      _cameras = cameras;

      final index = _cameraIndex % _cameras.length;
      await _openCamera(index);
    } catch (e) {
      if (!mounted || _appInBackground) return;

      setState(() {
        _error = _cameraErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _openCamera(int index) async {
    final previous = _controller;
    _controller = null;

    await previous?.dispose();

    if (!mounted || _appInBackground) return;

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.low,
      enableAudio: true,
    );

    try {
      await controller.initialize();

      if (!mounted || _appInBackground) {
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
        _error = _cameraErrorMessage(e);
        _loading = false;
      });
    }
  }

  // ==========================================
  // COUNTDOWN
  // ==========================================

  Future<void> _startCountdown() async {
    if (_busy ||
        _loading ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _appInBackground ||
        _selectedVideo != null) {
      return;
    }

    final camera = _controller;

    if (camera == null || !camera.value.isInitialized) {
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

    if (!mounted) return;

    setState(() {
      _isCountingDown = false;
      _countdownRemaining = 0;
    });
  }

  // ==========================================
  // RECORDING TIMER
  // ==========================================

  void _startTimer() {
    _timer?.cancel();

    _stopwatch
      ..reset()
      ..start();

    _recordingDuration = Duration.zero;

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
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
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
    _isImportedVideo = false;

    await previous?.dispose();
  }

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

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Playback error: $e';
      });
    }
  }

  // ==========================================
  // GALLERY IMPORT
  // ==========================================

  Future<void> _importVideo() async {
    if (_busy ||
        _loading ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _appInBackground) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);

      if (video == null || !mounted) return;

      await _clearSelectedVideo();
      await _prepareVideoPreview(video);

      if (!mounted) return;

      setState(() {
        _selectedVideo = video;
        _isImportedVideo = true;
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to import video: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ==========================================
  // START RECORDING + SENSORS
  // ==========================================

  Future<void> _startRecording() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isRecordingVideo ||
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
      await controller.startVideoRecording();

      if (!mounted) {
        await controller.stopVideoRecording();
        return;
      }

      _startTimer();

      try {
        await _sensorService.startRecording();
      } catch (e) {
        debugPrint('Sensor tracking unavailable: $e');
      }

      if (!mounted) {
        await _sensorService.stopRecording();

        if (controller.value.isRecordingVideo) {
          await controller.stopVideoRecording();
        }

        _stopTimer();
        return;
      }

      setState(() {
        _isRecording = true;
        _busy = false;
      });
    } catch (e) {
      _stopTimer();

      try {
        await _sensorService.stopRecording();
      } catch (sensorError) {
        debugPrint('Sensor cleanup error: $sensorError');
      }

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _busy = false;
        _error = _recordingErrorMessage(e);
      });
    }
  }

  // ==========================================
  // STOP RECORDING + SENSORS
  // ==========================================

  Future<void> _stopRecording() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isRecordingVideo ||
        _busy ||
        _savingProject) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    _stopTimer();

    try {
      final video = await controller.stopVideoRecording();
      await _sensorService.stopRecording();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
      });

      await _prepareVideoPreview(video);

      if (!mounted) return;

      setState(() {
        _selectedVideo = video;
        _isImportedVideo = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _error = _recordingErrorMessage(e);
      });
    } finally {
      try {
        await _sensorService.stopRecording();
      } catch (e) {
        debugPrint('Unable to stop sensors: $e');
      }

      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ==========================================
  // SAVE PROJECT
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
            'Project saving currently requires Android. '
            'Chrome supports recording, import and preview.',
          ),
        ),
      );
      return;
    }

    final video = _selectedVideo!;
    final player = _videoController;

    if (player == null || !player.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video metadata is not ready.')),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = titleController.text.trim();
                  if (value.isNotEmpty) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleController.dispose();
      });
    }

    if (!mounted || title == null || title.trim().isEmpty) {
      return;
    }

    final durationMs = player.value.duration.inMilliseconds;
    final size = player.value.size;
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
      _error = null;
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project "${project.title}" saved successfully!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to save project: $e')));
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
      if (!mounted) return;

      setState(() {
        _busy = false;
        _loading = false;
        _error = 'Unable to reopen camera: $e';
      });
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

        if (_isRecording || _busy || _savingProject) {
          return;
        }

        _cameraRelease ??= _releaseCameraForBackground().whenComplete(() {
          _cameraRelease = null;
        });
        break;

      case AppLifecycleState.resumed:
        _appInBackground = false;

        if (_isRecording || _busy || _savingProject) {
          return;
        }

        unawaited(_restoreCameraAfterBackground());
        break;

      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _releaseCameraForBackground() async {
    await _cameraInitialization;

    final camera = _controller;
    _controller = null;

    try {
      await camera?.dispose();
    } catch (e) {
      debugPrint('Camera release error: $e');
    }

    if (!mounted) return;

    setState(() {
      _loading = _selectedVideo == null;
    });
  }

  Future<void> _restoreCameraAfterBackground() async {
    await _cameraRelease;

    if (!mounted ||
        _appInBackground ||
        _isRecording ||
        _busy ||
        _savingProject) {
      return;
    }

    if (_selectedVideo != null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    final controller = _controller;

    if (controller != null && controller.value.isInitialized) {
      setState(() {
        _loading = false;
      });
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
    _stopwatch.stop();

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
  // CAMERA PREVIEW UI
  // ==========================================

  Widget _buildCameraPreview(CameraController controller) {
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),

            if (_showFramingGuide) const Positioned.fill(child: FramingGuide()),

            if (_isCountingDown)
              Positioned.fill(
                child: Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
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
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CAMERA CONTROLS
  // ==========================================

  Widget _buildCameraView(CameraController controller) {
    return Column(
      children: [
        Expanded(child: _buildCameraPreview(controller)),

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
            'Recording starts in $_countdownRemaining...',
            style: const TextStyle(fontWeight: FontWeight.bold),
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
                        if (value == null) return;
                        setState(() {
                          _selectedCountdown = value;
                        });
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
    final controller = _controller;
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
                  : controller != null && controller.value.isInitialized
                  ? _buildCameraView(controller)
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
                        child: Text(
                          'Imported video',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
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
