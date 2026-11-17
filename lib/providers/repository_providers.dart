import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../data/report_repository.dart';
import '../data/caption_repository.dart';
import '../features/analysis/analysis_service.dart';
import '../features/editor/engine/editor_engine.dart';
import '../features/editor/engine/method_channel_editor_engine.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository();
});

final captionRepositoryProvider = Provider<CaptionRepository>((ref) {
  return CaptionRepository();
});

final editorEngineProvider = Provider<EditorEngine>((ref) {
  return MethodChannelEditorEngine();
});

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return AnalysisService(
    projectRepository: ref.watch(projectRepositoryProvider),
    captionRepository: ref.watch(captionRepositoryProvider),
    reportRepository: ref.watch(reportRepositoryProvider),
    editorEngine: ref.watch(editorEngineProvider),
  );
});
