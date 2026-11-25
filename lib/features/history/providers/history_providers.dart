
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/project.dart';
import '../../../models/performance_report.dart';
import '../../../providers/repository_providers.dart';

final historyProjectsProvider = StreamProvider<List<Project>>((ref) {
  final repository = ref.watch(projectRepositoryProvider);
  return repository.watchProjects();
});

final projectReportsProvider =
    StreamProvider.family<List<PerformanceReport>, String>(
  (ref, projectId) {
    final repository = ref.watch(reportRepositoryProvider);
    return repository.watchReports(projectId);
  },
);
