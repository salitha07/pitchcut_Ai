import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../data/report_repository.dart';
import '../data/caption_repository.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository();
});

final captionRepositoryProvider = Provider<CaptionRepository>((ref) {
  return CaptionRepository();
});
