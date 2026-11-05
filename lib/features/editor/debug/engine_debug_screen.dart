import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';
import 'package:pitchcut_ai/models/caption.dart';

// TEMPORARY, remove before release.
class EngineDebugScreen extends StatefulWidget {
  const EngineDebugScreen({super.key});

  static const routeName = '/engine-debug';

  @override
  State<EngineDebugScreen> createState() => _EngineDebugScreenState();
}

class _EngineDebugScreenState extends State<EngineDebugScreen> {
  final _formKey = GlobalKey<FormState>();
  final _captionController = TextEditingController(text: 'Hello PitchCut');
  final _captionStartController = TextEditingController(text: '0');
  final _captionEndController = TextEditingController(text: '3000');
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController(text: '3000');
  final _cutAtController = TextEditingController(text: '1500');
  final _cropLeftController = TextEditingController(text: '0');
  final _cropTopController = TextEditingController(text: '0');
  final _cropWidthController = TextEditingController(text: '320');
  final _cropHeightController = TextEditingController(text: '180');
  final _engine = MethodChannelEditorEngine();

  String? _clipPath;
  final List<String> _mergePaths = [];
  String? _resultMessage;
  String? _errorMessage;
  bool _burnCaptions = false;
  bool _isExporting = false;
  bool _isBusy = false;
  double _progress = 0;
  int _rotationDegrees = 90;
  StreamSubscription<ExportEvent>? _exportSubscription;
  Completer<void>? _exportCompletion;
  final List<String> _actionLog = [];

  bool get _actionsEnabled => !_isExporting && !_isBusy;

  @override
  void dispose() {
    final completion = _exportCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
    final subscription = _exportSubscription;
    _exportSubscription = null;
    if (_isExporting && subscription != null) {
      unawaited(
        subscription.cancel().catchError((Object error) {
          debugPrint('Export subscription cleanup failed: $error');
        }),
      );
    }
    _captionController.dispose();
    _captionStartController.dispose();
    _captionEndController.dispose();
    _trimStartController.dispose();
    _trimEndController.dispose();
    _cutAtController.dispose();
    _cropLeftController.dispose();
    _cropTopController.dispose();
    _cropWidthController.dispose();
    _cropHeightController.dispose();
    super.dispose();
  }

  Future<String?> _pickVideo() async {
    final stopwatch = Stopwatch()..start();
    const arguments = {'type': 'video'};
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Select a video clip',
        type: FileType.video,
      );
      if (file == null) {
        _logAction(
          'pickVideo',
          arguments,
          duration: stopwatch.elapsed,
          result: 'Picker dismissed',
        );
        return null;
      }
      if (!mounted) {
        _logAction(
          'pickVideo',
          arguments,
          duration: stopwatch.elapsed,
          result: 'Screen closed',
        );
        return null;
      }
      final path = file.path;
      if (path == null) {
        _showError(
          'FILE_NOT_FOUND',
          'The selected video has no local file path.',
        );
        _logAction(
          'pickVideo',
          arguments,
          duration: stopwatch.elapsed,
          errorCode: 'FILE_NOT_FOUND',
          message: 'Selected video has no local file path.',
        );
        return null;
      }

      setState(() {
        _clipPath = path;
        _resultMessage = null;
        _errorMessage = null;
      });
      _logAction(
        'pickVideo',
        arguments,
        duration: stopwatch.elapsed,
        result: path,
      );
      return path;
    } on PlatformException catch (error) {
      if (mounted) _showPlatformError(error);
      _logAction(
        'pickVideo',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: error.code,
        message: error.message,
      );
    } catch (error) {
      if (mounted) _showError('PICKER_ERROR', error.toString());
      _logAction(
        'pickVideo',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: 'PICKER_ERROR',
        message: error.toString(),
      );
    }
    return null;
  }

  Future<void> _addMergeClip() async {
    final stopwatch = Stopwatch()..start();
    final path = await _pickVideo();
    if (path == null || !mounted) {
      _logAction(
        'addMergeClip',
        const {},
        duration: stopwatch.elapsed,
        result: 'No clip added',
      );
      return;
    }
    setState(() => _mergePaths.add(path));
    _logAction(
      'addMergeClip',
      const {},
      duration: stopwatch.elapsed,
      result: path,
    );
  }

  void _removeMergeClip(int index) {
    final path = _mergePaths[index];
    setState(() => _mergePaths.removeAt(index));
    _logAction(
      'removeMergeClip',
      {'index': index, 'path': path},
      duration: Duration.zero,
      result: 'Clip removed',
    );
  }

  String? _validateCaptionText(String? value) {
    if (!_burnCaptions) return null;
    if (value == null || value.trim().isEmpty) return 'Enter caption text.';
    return null;
  }

  String? _validateCaptionStart(String? value) {
    if (!_burnCaptions) return null;
    final startMs = int.tryParse(value ?? '');
    if (startMs == null) return 'Enter a whole number of milliseconds.';
    if (startMs < 0) return 'Start time must be 0 or greater.';
    return null;
  }

  String? _validateCaptionEnd(String? value) {
    if (!_burnCaptions) return null;
    final endMs = int.tryParse(value ?? '');
    if (endMs == null) return 'Enter a whole number of milliseconds.';
    final startMs = int.tryParse(_captionStartController.text);
    if (startMs != null && endMs <= startMs) {
      return 'End time must be greater than start time.';
    }
    return null;
  }

  Future<void> _export() async {
    final stopwatch = Stopwatch()..start();
    final selectedPath = _clipPath;
    final arguments = {
      'clipPaths': selectedPath == null ? <String>[] : [selectedPath],
      'captions': _burnCaptions
          ? [
              {
                'text': _captionController.text.trim(),
                'startMs': _captionStartController.text,
                'endMs': _captionEndController.text,
              },
            ]
          : <Map<String, String>>[],
      'targetHeight': null,
    };
    setState(() {
      _errorMessage = null;
      _resultMessage = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      _logAction(
        'export',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: 'INVALID_RANGE',
        message: 'Export form validation failed.',
      );
      return;
    }
    final path = selectedPath;
    if (path == null) {
      _showError('FILE_NOT_FOUND', 'Pick a video clip before exporting.');
      _logAction(
        'export',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: 'FILE_NOT_FOUND',
        message: 'Pick a video clip before exporting.',
      );
      return;
    }

    final captions = _burnCaptions
        ? [
            Caption(
              id: 'debug-caption',
              startMs: int.parse(_captionStartController.text),
              endMs: int.parse(_captionEndController.text),
              text: _captionController.text.trim(),
            ),
          ]
        : const <Caption>[];
    setState(() {
      _isExporting = true;
      _progress = 0;
    });
    final completed = Completer<void>();
    _exportCompletion = completed;
    String? outputPath;
    try {
      _exportSubscription = _engine
          .export(clipPaths: [path], captions: captions)
          .listen(
            (event) {
              outputPath = event.outputPath ?? outputPath;
              if (!mounted) return;
              setState(() {
                _progress = event.progress;
                if (event.outputPath != null) {
                  _resultMessage = 'Export succeeded:\n${event.outputPath}';
                }
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              final code = error is PlatformException
                  ? error.code
                  : 'EXPORT_FAILED';
              final message = error is PlatformException
                  ? error.message ?? error.toString()
                  : error.toString();
              if (mounted) _showError(code, message);
              _logAction(
                'export',
                arguments,
                duration: stopwatch.elapsed,
                errorCode: code,
                message: message,
              );
              if (!completed.isCompleted) completed.complete();
            },
            onDone: () {
              if (outputPath == null) {
                const message = 'Export ended without an output path.';
                if (mounted) _showError('EXPORT_FAILED', message);
                _logAction(
                  'export',
                  arguments,
                  duration: stopwatch.elapsed,
                  errorCode: 'EXPORT_FAILED',
                  message: message,
                );
              } else {
                _logAction(
                  'export',
                  arguments,
                  duration: stopwatch.elapsed,
                  result: outputPath,
                );
              }
              if (!completed.isCompleted) completed.complete();
            },
            cancelOnError: true,
          );
      await completed.future;
    } catch (error) {
      final code = error is PlatformException ? error.code : 'EXPORT_FAILED';
      final message = error is PlatformException
          ? error.message ?? error.toString()
          : error.toString();
      if (mounted) _showError(code, message);
      _logAction(
        'export',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: code,
        message: message,
      );
    } finally {
      _exportSubscription = null;
      _exportCompletion = null;
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _cancelExport() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _engine.cancelExport();
      _logAction(
        'cancelExport',
        const {},
        duration: stopwatch.elapsed,
        result: 'Cancellation requested',
      );
    } on PlatformException catch (error) {
      if (mounted) _showPlatformError(error);
      _logAction(
        'cancelExport',
        const {},
        duration: stopwatch.elapsed,
        errorCode: error.code,
        message: error.message,
      );
    } catch (error) {
      if (mounted) _showError('EXPORT_FAILED', error.toString());
      _logAction(
        'cancelExport',
        const {},
        duration: stopwatch.elapsed,
        errorCode: 'EXPORT_FAILED',
        message: error.toString(),
      );
    }
  }

  // TEMPORARY, remove before release.
  Future<void> _pingChannel() async {
    final stopwatch = Stopwatch()..start();
    const arguments = {
      'path': '/nonexistent/test.mp4',
      'startMs': 0,
      'endMs': 1000,
    };
    setState(() {
      _errorMessage = null;
      _resultMessage = null;
      _isBusy = true;
    });

    try {
      final result = await _engine.trim(
        path: '/nonexistent/test.mp4',
        startMs: 0,
        endMs: 1000,
      );
      final message = 'UNEXPECTED: trim returned "$result".';
      if (mounted) setState(() => _resultMessage = message);
      _logAction(
        'pingChannel',
        arguments,
        duration: stopwatch.elapsed,
        result: message,
      );
    } on PlatformException catch (error) {
      final message = '${error.code}: ${error.message ?? ''}';
      if (mounted) setState(() => _errorMessage = message);
      _logAction(
        'pingChannel',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: error.code,
        message: error.message,
      );
    } on MissingPluginException catch (error) {
      final message = 'CHANNEL NOT REGISTERED: ${error.message ?? ''}';
      if (mounted) setState(() => _errorMessage = message);
      _logAction(
        'pingChannel',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: 'MISSING_PLUGIN',
        message: message,
      );
    } catch (error) {
      final message = 'UNEXPECTED: ${error.runtimeType}: $error';
      if (mounted) setState(() => _errorMessage = message);
      _logAction(
        'pingChannel',
        arguments,
        duration: stopwatch.elapsed,
        errorCode: 'ERROR',
        message: message,
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<String> _requireClipPath() async {
    final path = _clipPath;
    if (path == null) {
      throw PlatformException(
        code: 'FILE_NOT_FOUND',
        message: 'Pick a video clip first.',
      );
    }
    return path;
  }

  Future<void> _runAction(
    String method,
    Map<String, Object?> arguments,
    Future<Object?> Function() execute,
  ) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _errorMessage = null;
      _resultMessage = null;
      _isBusy = true;
    });
    try {
      final result = await execute();
      if (mounted) {
        setState(() => _resultMessage = '$method succeeded:\n$result');
      }
      _logAction(
        method,
        arguments,
        duration: stopwatch.elapsed,
        result: result,
      );
    } on PlatformException catch (error) {
      if (mounted) _showPlatformError(error);
      _logAction(
        method,
        arguments,
        duration: stopwatch.elapsed,
        errorCode: error.code,
        message: error.message,
      );
    } catch (error) {
      if (mounted) _showError('EXPORT_FAILED', error.toString());
      _logAction(
        method,
        arguments,
        duration: stopwatch.elapsed,
        errorCode: 'EXPORT_FAILED',
        message: error.toString(),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  int _readInteger(TextEditingController controller, String name) {
    final value = int.tryParse(controller.text);
    if (value == null) {
      throw PlatformException(
        code: 'INVALID_RANGE',
        message: '$name must be a whole number.',
      );
    }
    return value;
  }

  void _showPlatformError(PlatformException error) {
    _showError(error.code, error.message ?? 'The operation failed.');
  }

  void _showError(String code, String message) {
    setState(() {
      _resultMessage = null;
      _errorMessage = '$code: $message';
    });
  }

  void _logAction(
    String method,
    Map<String, Object?> arguments, {
    required Duration duration,
    Object? result,
    String? errorCode,
    String? message,
  }) {
    final outcome = errorCode == null
        ? 'result=${jsonEncode(result)}'
        : 'error=$errorCode: ${message ?? ''}';
    final entry =
        '${DateTime.now().toIso8601String()} | $method | '
        'args=${jsonEncode(arguments)} | $outcome | ${duration.inMilliseconds} ms';
    debugPrint(entry);
    _actionLog.insert(0, entry);
    if (mounted) setState(() {});
  }

  Widget _integerField(
    String label,
    TextEditingController controller, {
    int? minimum,
    int? maximum,
  }) {
    return TextField(
      controller: controller,
      enabled: _actionsEnabled,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: minimum != null && maximum != null
            ? '$minimum-$maximum'
            : null,
      ),
    );
  }

  Widget _operationSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editor Engine Debug')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // TEMPORARY, remove before release.
            Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(
                'TEMPORARY, M4 engine debug',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            _operationSection('Video input', [
              // TEMPORARY, remove before release.
              OutlinedButton(
                onPressed: _actionsEnabled ? _pingChannel : null,
                child: const Text('Ping channel'),
              ),
              OutlinedButton.icon(
                onPressed: _actionsEnabled ? _pickVideo : null,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Pick video clip'),
              ),
              if (_clipPath case final path?) ...[
                const SizedBox(height: 8),
                SelectableText('Selected clip: $path'),
              ],
            ]),
            _operationSection('Export', [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Burn Captions'),
                      value: _burnCaptions,
                      onChanged: _actionsEnabled
                          ? (value) => setState(() => _burnCaptions = value)
                          : null,
                    ),
                    TextFormField(
                      controller: _captionController,
                      enabled: _actionsEnabled,
                      decoration: const InputDecoration(
                        labelText: 'Caption text',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateCaptionText,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('caption-start-ms'),
                            controller: _captionStartController,
                            enabled: _actionsEnabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'-?\d*'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Start (ms)',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateCaptionStart,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('caption-end-ms'),
                            controller: _captionEndController,
                            enabled: _actionsEnabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'-?\d*'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'End (ms)',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateCaptionEnd,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('export-button'),
                onPressed: _actionsEnabled ? _export : null,
                icon: const Icon(Icons.movie_creation_outlined),
                label: const Text('Export'),
              ),
              OutlinedButton.icon(
                onPressed: _isExporting ? _cancelExport : null,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Export'),
              ),
              if (_isExporting || _progress > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 4),
                Text('${(_progress * 100).round()}%'),
              ],
            ]),
            _operationSection('Trim', [
              Row(
                children: [
                  Expanded(
                    child: _integerField('Start (ms)', _trimStartController),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _integerField('End (ms)', _trimEndController),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _actionsEnabled
                    ? () => _runAction(
                        'trim',
                        {
                          'path': _clipPath,
                          'startMs': _trimStartController.text,
                          'endMs': _trimEndController.text,
                        },
                        () async {
                          final path = await _requireClipPath();
                          return _engine.trim(
                            path: path,
                            startMs: _readInteger(
                              _trimStartController,
                              'Start',
                            ),
                            endMs: _readInteger(_trimEndController, 'End'),
                          );
                        },
                      )
                    : null,
                child: const Text('Trim'),
              ),
            ]),
            _operationSection('Cut', [
              _integerField('Cut at (ms)', _cutAtController),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _actionsEnabled
                    ? () => _runAction(
                        'cut',
                        {'path': _clipPath, 'atMs': _cutAtController.text},
                        () async {
                          final path = await _requireClipPath();
                          return _engine.cut(
                            path: path,
                            atMs: _readInteger(_cutAtController, 'Cut time'),
                          );
                        },
                      )
                    : null,
                child: const Text('Cut'),
              ),
            ]),
            _operationSection('Merge', [
              OutlinedButton.icon(
                onPressed: _actionsEnabled ? _addMergeClip : null,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Add clip to merge'),
              ),
              for (var index = 0; index < _mergePaths.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Clip ${index + 1}'),
                  subtitle: Text(_mergePaths[index]),
                  trailing: IconButton(
                    tooltip: 'Remove clip',
                    onPressed: _actionsEnabled
                        ? () => _removeMergeClip(index)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
              FilledButton(
                onPressed: _actionsEnabled
                    ? () => _runAction(
                        'merge',
                        {'paths': List<String>.of(_mergePaths)},
                        () {
                          if (_mergePaths.length < 2) {
                            throw PlatformException(
                              code: 'INVALID_RANGE',
                              message: 'Add at least two clips to merge.',
                            );
                          }
                          return _engine.merge(paths: List.of(_mergePaths));
                        },
                      )
                    : null,
                child: const Text('Merge clips'),
              ),
            ]),
            _operationSection('Rotate', [
              DropdownButtonFormField<int>(
                initialValue: _rotationDegrees,
                decoration: const InputDecoration(
                  labelText: 'Degrees clockwise',
                  border: OutlineInputBorder(),
                ),
                items: const [90, 180, 270]
                    .map(
                      (degrees) => DropdownMenuItem(
                        value: degrees,
                        child: Text('$degrees°'),
                      ),
                    )
                    .toList(),
                onChanged: _actionsEnabled
                    ? (degrees) {
                        if (degrees != null) {
                          setState(() => _rotationDegrees = degrees);
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _actionsEnabled
                    ? () => _runAction(
                        'rotate',
                        {'path': _clipPath, 'degrees': _rotationDegrees},
                        () async {
                          final path = await _requireClipPath();
                          return _engine.rotate(
                            path: path,
                            degrees: _rotationDegrees,
                          );
                        },
                      )
                    : null,
                child: const Text('Rotate'),
              ),
            ]),
            _operationSection('Crop', [
              Row(
                children: [
                  Expanded(child: _integerField('Left', _cropLeftController)),
                  const SizedBox(width: 12),
                  Expanded(child: _integerField('Top', _cropTopController)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _integerField('Width', _cropWidthController)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _integerField('Height', _cropHeightController),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _actionsEnabled
                    ? () => _runAction(
                        'crop',
                        {
                          'path': _clipPath,
                          'left': _cropLeftController.text,
                          'top': _cropTopController.text,
                          'width': _cropWidthController.text,
                          'height': _cropHeightController.text,
                        },
                        () async {
                          final path = await _requireClipPath();
                          return _engine.crop(
                            path: path,
                            left: _readInteger(_cropLeftController, 'Left'),
                            top: _readInteger(_cropTopController, 'Top'),
                            width: _readInteger(_cropWidthController, 'Width'),
                            height: _readInteger(
                              _cropHeightController,
                              'Height',
                            ),
                          );
                        },
                      )
                    : null,
                child: const Text('Crop'),
              ),
            ]),
            _operationSection('Loudness', [
              FilledButton(
                onPressed: _actionsEnabled
                    ? () => _runAction(
                        'getLoudnessSamples',
                        {'path': _clipPath},
                        () async {
                          final path = await _requireClipPath();
                          return _engine.getLoudnessSamples(path);
                        },
                      )
                    : null,
                child: const Text('Get loudness samples'),
              ),
            ]),
            _operationSection('Results log', [
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _actionLog.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: _actionLog.join('\n')),
                          );
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy log'),
                ),
              ),
              SizedBox(
                height: 240,
                child: _actionLog.isEmpty
                    ? const Center(child: Text('No actions yet.'))
                    : ListView.separated(
                        itemCount: _actionLog.length,
                        itemBuilder: (context, index) => SelectableText(
                          _actionLog[index],
                          key: ValueKey('action-log-$index'),
                        ),
                        separatorBuilder: (_, _) => const Divider(height: 12),
                      ),
              ),
            ]),
            if (_isBusy) const LinearProgressIndicator(),
            if (_resultMessage case final result?) ...[
              const SizedBox(height: 8),
              Text(result, key: const ValueKey('operation-result')),
            ],
            if (_errorMessage case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const ValueKey('operation-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
