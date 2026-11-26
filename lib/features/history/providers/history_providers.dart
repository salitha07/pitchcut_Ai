import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/project.dart';
import '../../../models/performance_report.dart';
import '../../../providers/repository_providers.dart';

/// Live list of the signed-in user's projects.
final historyProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(projectRepositoryProvider).watchProjects();
});

/// Live performance reports for an individual project.
final projectReportsProvider =
    StreamProvider.family<List<PerformanceReport>, String>((ref, projectId) {
      return ref.watch(reportRepositoryProvider).watchReports(projectId);
    });

// Compatibility aliases for develop branch references.
final projectsProvider = historyProjectsProvider;
final reportsProvider = projectReportsProvider;
