import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/project.dart';
import '../../models/performance_report.dart';
import 'providers/history_providers.dart';

class ProjectHistoryScreen extends ConsumerWidget {
  const ProjectHistoryScreen({
    super.key,
    required this.project,
  });

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(
      projectReportsProvider(project.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(project.title),
      ),
      body: reportsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load reports: $error'),
          ),
        ),
        data: (reports) {
          if (reports.isEmpty) {
            return const Center(
              child: Text(
                'No performance reports for this project yet.',
              ),
            );
          }

          final sortedReports = reports.toList()
            ..sort(
              (a, b) => b.createdAt.compareTo(a.createdAt),
            );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Score over time',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              _ScoreTrendChart(
                reports: sortedReports,
              ),

              const SizedBox(height: 24),

              Text(
                'Previous Reports (${sortedReports.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              ...sortedReports.map(
                (report) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text('${report.score}'),
                    ),
                    title: Text(
                      'Performance score: ${report.score}/100',
                    ),
                    subtitle: Text(
                      _formatDate(report.createdAt),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReportDetailScreen(
                            report: report,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --------------------------------------------------
// PERFORMANCE REPORT DETAILS
// --------------------------------------------------

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({
    super.key,
    required this.report,
  });

  final PerformanceReport report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Report'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  'Overall Performance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                CircleAvatar(
                  radius: 54,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    '${report.score}',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Score out of 100'),
                const SizedBox(height: 8),
                Text(_formatDate(report.createdAt)),
              ],
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Performance Breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),

          _scoreRow('Face Position', report.faceScore),
          _scoreRow('Camera Stability', report.stabilityScore),
          _scoreRow('Speaking Pace', report.paceScore),

          const SizedBox(height: 20),

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
                leading: const Icon(
                  Icons.pause_circle_outline,
                ),
                title: Text(
                  '${_formatTime(pause.startMs)} - '
                  '${_formatTime(pause.endMs)}',
                ),
                subtitle: Text(
                  'Duration: '
                  '${(pause.durationMs / 1000).toStringAsFixed(1)} seconds'
                  '${pause.clipIndex == null ? '' : ' • Clip ${pause.clipIndex! + 1}'}',
                ),
              ),
            ),

          const SizedBox(height: 20),

          Text(
            'Improvement Tips',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),

          if (report.tips.isEmpty)
            const Text('No improvement tips available.')
          else
            ...report.tips.map(
              (tip) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.lightbulb_outline,
                ),
                title: Text(tip),
              ),
            ),
        ],
      ),
    );
  }

  Widget _scoreRow(String title, int? score) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Text(
        score == null ? 'Unavailable' : '$score / 100',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// --------------------------------------------------
// SCORE TREND CHART
// --------------------------------------------------

class _ScoreTrendChart extends StatelessWidget {
  const _ScoreTrendChart({
    required this.reports,
  });

  final List<PerformanceReport> reports;

  @override
  Widget build(BuildContext context) {
    final chronological = reports.toList()
      ..sort(
        (a, b) => a.createdAt.compareTo(b.createdAt),
      );

    final color = Theme.of(context).colorScheme.primary;
    final gridColor = Theme.of(context).dividerColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _ScoreChartPainter(
              reports: chronological,
              lineColor: color,
              gridColor: gridColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreChartPainter extends CustomPainter {
  _ScoreChartPainter({
    required this.reports,
    required this.lineColor,
    required this.gridColor,
  });

  final List<PerformanceReport> reports;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (reports.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    const left = 12.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 12.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = top + chartHeight * i / 4;

      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    Offset position(int index) {
      final x = reports.length == 1
          ? left + chartWidth / 2
          : left + chartWidth * index / (reports.length - 1);

      final score = reports[index].score.clamp(0, 100);
      final y = top + chartHeight * (1 - score / 100);

      return Offset(x, y);
    }

    final path = Path()
      ..moveTo(
        position(0).dx,
        position(0).dy,
      );

    for (var i = 1; i < reports.length; i++) {
      final point = position(i);
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, linePaint);

    for (var i = 0; i < reports.length; i++) {
      canvas.drawCircle(
        position(i),
        4,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _ScoreChartPainter oldDelegate,
  ) {
    return oldDelegate.reports != reports ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

// --------------------------------------------------
// DATE AND TIME HELPERS
// --------------------------------------------------

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

  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}