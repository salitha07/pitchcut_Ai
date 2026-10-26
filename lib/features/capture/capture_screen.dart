import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        throw Exception('No camera found on this device.');
      }

      await _openCamera(_cameraIndex);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code.toLowerCase().contains('denied')
            ? 'Camera permission denied. Allow camera access in browser settings.'
            : 'Camera error: ${e.description ?? e.code}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCamera(int index) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
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
    if (_cameras.length < 2 || _loading) return;

    setState(() => _loading = true);

    try {
      final next = (_cameraIndex + 1) % _cameras.length;
      await _openCamera(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to switch camera: $e';
        _loading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Camera lifecycle handling will be added for Android testing.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Record Video')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, size: 56),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _initializeCamera,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              )
            : controller != null && controller.value.isInitialized
            ? Column(
                children: [
                  Expanded(child: Center(child: CameraPreview(controller))),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ElevatedButton.icon(
                      onPressed: _cameras.length > 1 ? _switchCamera : null,
                      icon: const Icon(Icons.cameraswitch),
                      label: const Text('Switch Camera'),
                    ),
                  ),
                ],
              )
            : const Text('Camera unavailable'),
      ),
    );
  }
}
