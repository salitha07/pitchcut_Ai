import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/project.dart';
import '../../models/performance_report.dart';
import 'providers/history_providers.dart';

class ProjectHistoryScreen extends ConsumerWidget {
  const ProjectHistoryScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsProvider(project.id));

    return Scaffold(
      appBar: AppBar(title: Text(project.title)),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Error loading reports: $error')),
        data: (reports) {
          if (reports.isEmpty) {
            return const Center(child: Text('No performance reports yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Score over time',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _ScoreChart(reports: reports),
              const SizedBox(height: 24),
              Text(
                'Previous Reports',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...reports.map(
                (report) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${report.score}')),
                    title: Text('Performance Score: ${report.score}/100'),
                    subtitle: Text(_formatDate(report.createdAt)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReportDetailScreen(report: report),
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

class _ScoreChart extends StatelessWidget {
  const _ScoreChart({required this.reports});

  final List<PerformanceReport> reports;

  @override
  Widget build(BuildContext context) {
    final chronologicalReports = reports.reversed.toList();

    return SizedBox(
      height: 190,
      child: CustomPaint(
        painter: _ScoreChartPainter(
          scores: chronologicalReports
              .map((report) => report.score.toDouble())
              .toList(),
          lineColor: Theme.of(context).colorScheme.primary,
          gridColor: Theme.of(context).dividerColor,
          textColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScoreChartPainter extends CustomPainter {
  _ScoreChartPainter({
    required this.scores,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<double> scores;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 25.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final value in [0, 25, 50, 75, 100]) {
      final y = top + chartHeight * (1 - value / 100);

      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );

      textPainter.text = TextSpan(
        text: '$value',
        style: TextStyle(color: textColor, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));
    }

    if (scores.isEmpty) return;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final points = <Offset>[];

    for (var i = 0; i < scores.length; i++) {
      final x = scores.length == 1
          ? left + chartWidth / 2
          : left + chartWidth * i / (scores.length - 1);

      final score = scores[i].clamp(0.0, 100.0);
      final y = top + chartHeight * (1 - score / 100);

      points.add(Offset(x, y));
    }

    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);

      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(path, linePaint);
    }

    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreChartPainter oldDelegate) {
    return oldDelegate.scores != scores ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.report});

  final PerformanceReport report;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              '${report.score}/100',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          const Center(child: Text('Overall Score')),
          const SizedBox(height: 24),
          _scoreRow('Face Score', report.faceScore),
          _scoreRow('Stability Score', report.stabilityScore),
          _scoreRow('Pace Score', report.paceScore),
          const SizedBox(height: 24),
          Text('Report Date', style: Theme.of(context).textTheme.titleMedium),
          Text(_formatDate(report.createdAt)),
          const SizedBox(height: 24),
          Text(
            'Tips for Improvement',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (report.tips.isEmpty)
            const Text('No tips available.')
          else
            ...report.tips.map(
              (tip) => ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(tip),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Detected Pauses (${report.pauses.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (report.pauses.isEmpty)
            const Text('No pauses detected.')
          else
            ...report.pauses.asMap().entries.map((entry) {
              final index = entry.key;
              final pause = entry.value;

              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text('Start: ${_formatDuration(pause.startMs)}'),
                  subtitle: Text(
                    'End: ${_formatDuration(pause.endMs)}\n'
                    'Duration: ${_formatDuration(pause.durationMs)}'
                    '${pause.clipIndex != null ? '\nClip: ${pause.clipIndex! + 1}' : ''}',
                  ),
                  isThreeLine: true,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _scoreRow(String label, int? score) {
    return ListTile(
      title: Text(label),
      trailing: Text(score == null || score == -1 ? 'N/A' : '$score/100'),
    );
  }
}

String _formatDate(String iso) {
  if (iso.length >= 10) {
    return iso.substring(0, 10);
  }
  return iso;
}

String _formatDuration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final remainingMs = milliseconds % 1000;

  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${remainingMs.toString().padLeft(3, '0')}';
}
