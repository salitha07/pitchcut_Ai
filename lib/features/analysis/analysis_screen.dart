
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/caption.dart' as m7;
import '../../models/clip.dart';
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
  late Future<List<Clip>> _clipsFuture;
  late Future<List<PerformanceReport>> _reportsFuture;

  String? _selectedProjectId;
  String? _dataProjectId;

  PerformanceReport? _report;

  final Set<String> _analysingClipIds = {};

  bool _isAnalysing = false;
  bool _isOpeningEditor = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _selectedProjectId = widget.projectId;
    _projectsFuture = ref.read(projectRepositoryProvider).getProjects();

    _clipsFuture = Future.value([]);
    _reportsFuture = Future.value([]);

    if (_selectedProjectId != null && _selectedProjectId!.isNotEmpty) {
      _loadProjectData(_selectedProjectId!);
    }
  }

  void _loadProjectData(String projectId) {
    _dataProjectId = projectId;

    _clipsFuture = ref
        .read(projectRepositoryProvider)
        .getClips(projectId);

    _reportsFuture = ref
        .read(reportRepositoryProvider)
        .getReports(projectId);
  }

  Future<void> _refreshReports() async {
    final projectId = _selectedProjectId;

    if (projectId == null) return;

    setState(() {
      _reportsFuture = ref
          .read(reportRepositoryProvider)
          .getReports(projectId);
    });
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

      await _refreshReports();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isAnalysing = false;
      });
    }
  }

  Future<void> _analyseVideo(Clip clip) async {
    if (_analysingClipIds.contains(clip.id) || _isAnalysing) return;

    final projectId = _selectedProjectId;

    if (projectId == null) return;

    setState(() {
      _analysingClipIds.add(clip.id);
      _error = null;
    });

    try {
      final report = await ref
          .read(analysisServiceProvider)
          .analyseVideo(projectId, clip.id);

      if (!mounted) return;

      setState(() {
        _report = report;
        _analysingClipIds.remove(clip.id);
      });

      await _refreshReports();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'Video analysis failed: $error';
        _analysingClipIds.remove(clip.id);
      });
    }
  }

  void _showReport(PerformanceReport report) {
    setState(() {
      _report = report;
      _error = null;
    });
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

      var captions = const <m7.Caption>[];

      try {
        captions = await ref
            .read(captionRepositoryProvider)
            .getCaptions(project.id);
      } catch (_) {
        // The editor can still open if captions cannot be loaded.
      }

      if (!mounted) return;

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
            captions: captions,
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

      String? clipId = pause.clipId;

      if ((clipId == null || clipId.isEmpty) &&
          pause.clipIndex != null &&
          pause.clipIndex! >= 0 &&
          pause.clipIndex! < sourceClips.length) {
        clipId = sourceClips[pause.clipIndex!].id as String;
      }

      if (clipId == null || clipId.isEmpty) continue;

      VideoClip? matchingClip;

      for (final clip in timeline.clips) {
        if (clip.sourceClipId != clipId) continue;

        final sourceStartMs = clip.sourceStart.inMilliseconds;
        final sourceEndMs = clip.sourceEnd.inMilliseconds;

        if (pause.startMs >= sourceStartMs &&
            pause.endMs <= sourceEndMs) {
          matchingClip = clip;
          break;
        }
      }

      if (matchingClip == null) continue;

      final localStartMs =
          pause.startMs - matchingClip.sourceStart.inMilliseconds;

      final localEndMs =
          pause.endMs - matchingClip.sourceStart.inMilliseconds;

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

          if (selectedId != null && _dataProjectId != selectedId) {
            _loadProjectData(selectedId);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Analyse your presentation',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Analyse individual videos or evaluate your complete project.',
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
                    child: Text(
                      project.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _isAnalysing ||
                        _analysingClipIds.isNotEmpty ||
                        _isOpeningEditor
                    ? null
                    : (value) {
                        setState(() {
                          _selectedProjectId = value;
                          _report = null;
                          _error = null;

                          if (value != null) {
                            _loadProjectData(value);
                          } else {
                            _dataProjectId = null;
                            _clipsFuture = Future.value([]);
                            _reportsFuture = Future.value([]);
                          }
                        });
                      },
              ),

              if (selectedId != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Project Videos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),

                FutureBuilder<List<Clip>>(
                  future: _clipsFuture,
                  builder: (context, clipSnapshot) {
                    if (clipSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (clipSnapshot.hasError) {
                      return _errorCard(
                        'Could not load project videos: '
                        '${clipSnapshot.error}',
                      );
                    }

                    final clips = clipSnapshot.data ?? [];

                    if (clips.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No videos found in this project.'),
                        ),
                      );
                    }

                    return FutureBuilder<List<PerformanceReport>>(
                      future: _reportsFuture,
                      builder: (context, reportSnapshot) {
                        if (reportSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (reportSnapshot.hasError) {
                          return _errorCard(
                            'Could not load saved reports: '
                            '${reportSnapshot.error}',
                          );
                        }

                        final reports = reportSnapshot.data ?? [];

                        return Column(
                          children: clips.map((clip) {
                            final videoReports = reports.where(
                              (report) =>
                                  report.reportType == 'video' &&
                                  report.clipId == clip.id,
                            ).toList();

                            videoReports.sort(
                              (a, b) =>
                                  b.createdAt.compareTo(a.createdAt),
                            );

                            final latestReport = videoReports.isEmpty
                                ? null
                                : videoReports.first;

                            final isBusy =
                                _analysingClipIds.contains(clip.id);

                            return _buildVideoCard(
                              clip: clip,
                              latestReport: latestReport,
                              isBusy: isBusy,
                            );
                          }).toList(),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 24),

                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _isAnalysing ||
                            _analysingClipIds.isNotEmpty ||
                            _isOpeningEditor
                        ? null
                        : _analyse,
                    icon: _isAnalysing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.analytics_outlined),
                    label: Text(
                      _isAnalysing
                          ? 'Analysing Project...'
                          : 'Analyse Entire Project',
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  'This analyses all videos together and saves an overall report.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),

                const SizedBox(height: 24),

                FutureBuilder<List<PerformanceReport>>(
                  future: _reportsFuture,
                  builder: (context, reportSnapshot) {
                    if (!reportSnapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final projectReports = reportSnapshot.data!
                        .where((report) => report.reportType == 'project')
                        .toList();

                    if (projectReports.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    projectReports.sort(
                      (a, b) => b.createdAt.compareTo(a.createdAt),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved Project Reports',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        ...projectReports.map(
                          (report) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.assessment_outlined),
                              title: Text('Project Score: ${report.score}/100'),
                              subtitle: Text(
                                _formatDate(report.createdAt),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showReport(report),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],

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

  Widget _buildVideoCard({
    required Clip clip,
    required PerformanceReport? latestReport,
    required bool isBusy,
  }) {
    final fileName = _fileName(clip.localPath);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.video_file_outlined, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDuration(clip.durationMs)}  •  '
                        '${clip.width} × ${clip.height}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (latestReport != null)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Latest score: ${latestReport.score}/100',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showReport(latestReport),
                    child: const Text('View Report'),
                  ),
                ],
              )
            else
              const Text(
                'Not analysed yet',
                style: TextStyle(color: Colors.grey),
              ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy ||
                        _isAnalysing ||
                        _isOpeningEditor ||
                        _analysingClipIds.isNotEmpty
                    ? null
                    : () => _analyseVideo(clip),
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(
                  isBusy
                      ? 'Analysing Video...'
                      : latestReport == null
                          ? 'Analyse This Video'
                          : 'Analyse Again',
                ),
              ),
            ),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }

  Widget _buildReport(PerformanceReport report, Project project) {
    final isVideoReport = report.reportType == 'video';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),

        Text(
          isVideoReport ? 'Individual Video Report' : 'Overall Project Report',
          style: Theme.of(context).textTheme.titleLarge,
        ),

        const SizedBox(height: 16),

        Center(
          child: Column(
            children: [
              Text(
                'Performance Score',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              CircleAvatar(
                radius: 58,
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
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
              onPressed: _isOpeningEditor ||
                      _isAnalysing ||
                      _analysingClipIds.isNotEmpty
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

        Text(
          'Improvement Tips',
          style: Theme.of(context).textTheme.titleLarge,
        ),

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

        Text(
          'Generated: ${_formatDate(report.createdAt)}',
          style: Theme.of(context).textTheme.bodySmall,
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

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);

    if (date == null) return value;

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
