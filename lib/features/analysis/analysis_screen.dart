import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/performance_report.dart';
import '../../models/project.dart';
import '../../providers/repository_providers.dart';
import '../editor/models/editor_suggestion.dart';
import '../editor/models/video_clip.dart';
import '../editor/services/editor_project_store.dart';
import '../editor/services/m5_project_library_service.dart';
import '../editor/services/project_clip_adapter.dart';
import '../editor/video_editor_screen.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key, this.projectId});

  final String? projectId;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  late Future<List<Project>> _projectsFuture;

  String? _selectedProjectId;
  PerformanceReport? _report;

  bool _isAnalysing = false;
  bool _isOpeningEditor = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _selectedProjectId = widget.projectId;
    _projectsFuture = ref.read(projectRepositoryProvider).getProjects();
  }

  Future<void> _analyse() async {
    final projectId = _selectedProjectId;

    if (projectId == null || projectId.isEmpty) {
      setState(() => _error = 'Please select a project first.');
      return;
    }

    setState(() {
      _isAnalysing = true;
      _error = null;
      _report = null;
    });

    try {
      final report = await ref
          .read(analysisServiceProvider)
          .analyseProject(projectId);

      if (!mounted) return;

      setState(() {
        _report = report;
        _isAnalysing = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isAnalysing = false;
      });
    }
  }

  /// Opens the selected project in the video editor with AI pause suggestions.
  Future<void> _openEditorWithSuggestions(
    Project project,
    PerformanceReport report,
  ) async {
    if (_isOpeningEditor) return;

    setState(() {
      _isOpeningEditor = true;
      _error = null;
    });

    try {
      final projectStore = EditorProjectStore();

      final projectLibrary = M5ProjectLibraryService(
        projectRepository: ref.read(projectRepositoryProvider),
        projectStore: projectStore,
      );

      final selection = await projectLibrary.selectProject(project);

      if (!mounted) return;

      final timeline = selection.timeline;

      if (!selection.canOpen || timeline == null) {
        throw StateError(
          selection.errorMessage ??
              'Could not open this project in the editor.',
        );
      }

      final suggestions = _createPauseSuggestions(
        report: report,
        timeline: timeline,
        sourceClips: selection.sourceClips,
      );

      if (suggestions.isEmpty) {
        throw StateError(
          'No detected pauses can be safely removed from the current timeline.',
        );
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoEditorScreen(
            videoPath: timeline.clips.first.path,
            videoName: timeline.clips.first.name,
            project: project,
            projectClips: selection.sourceClips,
            initialTimeline: timeline,
            projectStore: projectStore,
            suggestions: suggestions,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not open the editor: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningEditor = false;
        });
      }
    }
  }

  /// Converts detected pauses into safe, actionable editor suggestions.
  List<EditorSuggestion> _createPauseSuggestions({
    required PerformanceReport report,
    required ProjectEditorTimeline timeline,
    required List<dynamic> sourceClips,
  }) {
    final suggestions = <EditorSuggestion>[];

    for (final pause in report.pauses) {
      if (!pause.isValid) continue;

      // Resolve the original source clip ID.
      String? clipId = pause.clipId;

      if ((clipId == null || clipId.isEmpty) &&
          pause.clipIndex != null &&
          pause.clipIndex! >= 0 &&
          pause.clipIndex! < sourceClips.length) {
        clipId = sourceClips[pause.clipIndex!].id as String;
      }

      if (clipId == null || clipId.isEmpty) continue;

      // Find the timeline clip containing this complete source pause.
      VideoClip? matchingClip;

      for (final clip in timeline.clips) {
        if (clip.sourceClipId != clipId) continue;

        final sourceStartMs = clip.sourceStart.inMilliseconds;
        final sourceEndMs = clip.sourceEnd.inMilliseconds;

        if (pause.startMs >= sourceStartMs && pause.endMs <= sourceEndMs) {
          matchingClip = clip;
          break;
        }
      }

      if (matchingClip == null) continue;

      // Convert source timestamps into local timeline clip timestamps.
      final localStartMs =
          pause.startMs - matchingClip.sourceStart.inMilliseconds;

      final localEndMs = pause.endMs - matchingClip.sourceStart.inMilliseconds;

      // Keep at least 500ms on both sides of the removed range.
      if (localStartMs < 500 ||
          localEndMs <= localStartMs ||
          matchingClip.duration.inMilliseconds - localEndMs < 500) {
        continue;
      }

      final durationSeconds = (pause.endMs - pause.startMs) / 1000;

      suggestions.add(
        EditorSuggestion(
          id: 'pause-$clipId-${pause.startMs}-${pause.endMs}',
          title: 'Remove detected pause',
          details:
              'AI detected a ${durationSeconds.toStringAsFixed(1)} '
              'second pause. Review and remove this section.',
          startTime: Duration(milliseconds: pause.startMs),
          endTime: Duration(milliseconds: pause.endMs),
          action: RemovePauseSuggestionAction(
            clipId: clipId,
            startMs: pause.startMs,
            endMs: pause.endMs,
          ),
        ),
      );
    }

    return suggestions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance Analysis')),
      body: FutureBuilder<List<Project>>(
        future: _projectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _message('Could not load projects: ${snapshot.error}');
          }

          final projects = snapshot.data ?? [];

          if (projects.isEmpty) {
            return _message(
              'No projects found. Create a video project before analysis.',
            );
          }

          final selectedId =
              projects.any((project) => project.id == _selectedProjectId)
              ? _selectedProjectId
              : null;

          final selectedProject = selectedId == null
              ? null
              : projects.firstWhere((project) => project.id == selectedId);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Analyse your presentation',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Review speaking pace, face positioning, camera stability '
                'and pauses in your video.',
              ),
              const SizedBox(height: 24),

              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(
                  labelText: 'Select project',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.video_library_outlined),
                ),
                items: projects.map((project) {
                  return DropdownMenuItem(
                    value: project.id,
                    child: Text(project.title, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _isAnalysing || _isOpeningEditor
                    ? null
                    : (value) {
                        setState(() {
                          _selectedProjectId = value;
                          _report = null;
                          _error = null;
                        });
                      },
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isAnalysing || _isOpeningEditor ? null : _analyse,
                  icon: _isAnalysing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.analytics_outlined),
                  label: Text(
                    _isAnalysing ? 'Analysing...' : 'Analyse Project',
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                _errorCard(_error!),
              ],

              if (_report != null && selectedProject != null) ...[
                const SizedBox(height: 24),
                _buildReport(_report!, selectedProject),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _message(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }

  Widget _buildReport(PerformanceReport report, Project project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                'Overall Performance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              CircleAvatar(
                radius: 58,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  '${report.score}',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Score out of 100'),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Performance Breakdown',
          style: Theme.of(context).textTheme.titleLarge,
        ),

        const SizedBox(height: 12),

        _scoreRow('Face Position', report.faceScore),
        _scoreRow('Camera Stability', report.stabilityScore),
        _scoreRow('Speaking Pace', report.paceScore),

        const SizedBox(height: 24),

        Text(
          'Detected Pauses (${report.pauses.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),

        const SizedBox(height: 8),

        if (report.pauses.isEmpty)
          const Text('No long pauses detected.')
        else
          ...report.pauses.map(
            (pause) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pause_circle_outline),
              title: Text(
                '${_formatTime(pause.startMs)} - '
                '${_formatTime(pause.endMs)}',
              ),
              subtitle: Text(
                'Duration: '
                '${((pause.endMs - pause.startMs) / 1000).toStringAsFixed(1)} '
                'seconds',
              ),
            ),
          ),

        if (report.pauses.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isOpeningEditor || _isAnalysing
                  ? null
                  : () => _openEditorWithSuggestions(project, report),
              icon: _isOpeningEditor
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.video_library_outlined),
              label: Text(
                _isOpeningEditor
                    ? 'Opening Editor...'
                    : 'Review Pauses in Editor',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Review AI-detected pauses and choose which sections to remove.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],

        const SizedBox(height: 24),

        Text('Improvement Tips', style: Theme.of(context).textTheme.titleLarge),

        const SizedBox(height: 8),

        ...report.tips.map(
          (tip) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(tip),
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Report saved successfully.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _scoreRow(String title, int? score) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Text(
        score == null ? 'Unavailable' : '$score / 100',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatTime(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
