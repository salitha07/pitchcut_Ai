import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/performance_report.dart';
import '../../../models/project.dart';
import '../../../providers/repository_providers.dart';

/// Live list of the user's projects, newest first.
final projectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(projectRepositoryProvider).watchProjects().map((projects) {
    final sorted = [...projects];
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  });
});

/// Live list of reports for one project, newest first.
final reportsProvider =
    StreamProvider.family<List<PerformanceReport>, String>((ref, projectId) {
      return ref.watch(reportRepositoryProvider).watchReports(projectId);
    });