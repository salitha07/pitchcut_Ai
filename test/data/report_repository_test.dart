import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/report_repository.dart';
import 'package:pitchcut_ai/models/performance_report.dart';
import 'package:pitchcut_ai/models/pause_segment.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ReportRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'test-user-123'),
    );

    repository = ReportRepository(firestore: firestore, auth: auth);
  });

  group('ReportRepository', () {
    const projectId = 'project-1';

    final report1 = PerformanceReport(
      id: 'report-1',
      projectId: projectId,
      createdAt: '2026-10-15T10:00:00.000Z',
      score: 75,
      pauses: const <PauseSegment>[],
      faceScore: 80,
      stabilityScore: 70,
      paceScore: 75,
      tips: const ['Speak clearly'],
    );

    final report2 = PerformanceReport(
      id: 'report-2',
      projectId: projectId,
      createdAt: '2026-10-16T10:00:00.000Z',
      score: 90,
      pauses: const <PauseSegment>[],
      faceScore: 90,
      stabilityScore: 85,
      paceScore: 95,
      tips: const ['Great performance'],
    );

    test('saves and loads a report', () async {
      await repository.saveReport(report1);

      final reports = await repository.getReports(projectId);

      expect(reports, hasLength(1));
      expect(reports.first.id, 'report-1');
      expect(reports.first.score, 75);
    });

    test('returns reports newest first', () async {
      await repository.saveReport(report1);
      await repository.saveReport(report2);

      final reports = await repository.getReports(projectId);

      expect(reports, hasLength(2));
      expect(reports.first.id, 'report-2');
      expect(reports.last.id, 'report-1');
    });

    test('deletes a report', () async {
      await repository.saveReport(report1);

      await repository.deleteReport(projectId, report1.id);

      final reports = await repository.getReports(projectId);

      expect(reports, isEmpty);
    });

    test('deletes all reports for a project', () async {
      await repository.saveReport(report1);
      await repository.saveReport(report2);

      await repository.deleteAllReports(projectId);

      final reports = await repository.getReports(projectId);

      expect(reports, isEmpty);
    });

    test('rejects access when the user is signed out', () async {
      final signedOutAuth = MockFirebaseAuth(signedIn: false);

      final signedOutRepository = ReportRepository(
        firestore: firestore,
        auth: signedOutAuth,
      );

      expect(
        () => signedOutRepository.getReports(projectId),
        throwsA(isA<StateError>()),
      );
    });
  });
}
