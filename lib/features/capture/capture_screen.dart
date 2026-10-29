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

  String? _error;
  XFile? _selectedVideo;

  // Countdown
  int _selectedCountdown = 3;
  int _countdownRemaining = 0;
  int _countdownToken = 0;

  // Recording timer
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  // ==========================================
  // CAMERA INITIALIZATION
  // ==========================================

  Future<void> _initializeCamera() async {
    if (!mounted ||
        _busy ||
        _savingProject ||
        _isRecording ||
        _isCountingDown) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        throw Exception('No camera found on this device.');
      }

      final index = _cameraIndex % _cameras.length;
      await _openCamera(index);
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
            'Allow access in device or browser settings '
            'and try again.';
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
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
        _selectedVideo != null) {
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

  // ==========================================
  // COUNTDOWN
  // ==========================================

  Future<void> _startCountdown() async {
    if (_busy ||
        _loading ||
        _savingProject ||
        _isRecording ||
        _isCountingDown ||
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

      if (!mounted || token != _countdownToken || !_isCountingDown) {
        return;
      }

      setState(() {
        _countdownRemaining--;
      });
    }

    if (!mounted || token != _countdownToken) {
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
  // START RECORDING + SENSOR TRACKING
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
        _selectedVideo != null) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _clearSelectedVideo();

      // Start video capture first.
      await controller.startVideoRecording();

      if (!mounted) {
        await controller.stopVideoRecording();
        return;
      }

      // Start the UI recording timer.
      _startTimer();

      // Start collecting accelerometer and gyroscope data.
      // A sensor failure must not stop video recording.
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
        _error = 'Unable to start recording: $e';
      });
    }
  }

  // ==========================================
  // STOP RECORDING + STOP SENSOR TRACKING
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

      // Stop sensors after recording finishes.
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
        _error = 'Unable to stop or preview recording: $e';
      });
    } finally {
      // Always release sensor subscriptions.
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
  // SAVE PROJECT + SENSOR JSON
  // ==========================================

  Future<void> _saveProject() async {
    if (_savingProject ||
        _busy ||
        _isRecording ||
        _isCountingDown ||
        _selectedVideo == null) {
      return;
    }

    // Local absolute paths are supported on Android,
    // not in this Chrome prototype.
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Project saving currently requires Android. '
            'Chrome supports recording, import and preview.',
          ),
          duration: Duration(seconds: 5),
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
      text: 'PitchCut Video ${DateTime.now().millisecondsSinceEpoch}',
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
                hintText: 'Enter project title',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid video duration or resolution.')),
      );
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

        // Recorded video: include captured sensor data.
        // Gallery import: sensor path remains null.
        sensorService: _sensorService,
        isImportedVideo: _isImportedVideo,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project "${project.title}" saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save project: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
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
    if (_busy || _savingProject || _isRecording || _isCountingDown) {
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
  // LIFECYCLE
  // ==========================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Full Android interruption handling is pending.
    // Verify camera recovery on a real Android device.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _countdownToken++;
    _stopTimer();
    _stopwatch.stop();

    // Stop active sensor subscriptions.
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
            'REC  ${_formatDuration(_recordingDuration)}',
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
