import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/performance_report.dart';

class ReportRepository {
  ReportRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please log in to manage reports.');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> _reports(String projectId) {
    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('projects')
        .doc(projectId)
        .collection('reports');
  }

  Future<void> saveReport(PerformanceReport report) async {
    await _reports(report.projectId).doc(report.id).set(report.toJson());
  }

  Future<List<PerformanceReport>> getReports(String projectId) async {
    final snapshot = await _reports(projectId).get();

    final reports = snapshot.docs
        .map((doc) => PerformanceReport.fromJson(doc.data()))
        .toList();

    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  Stream<List<PerformanceReport>> watchReports(String projectId) {
    return _reports(projectId).snapshots().map((snapshot) {
      final reports = snapshot.docs
          .map((doc) => PerformanceReport.fromJson(doc.data()))
          .toList();

      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reports;
    });
  }

  Future<void> deleteReport(String projectId, String reportId) async {
    await _reports(projectId).doc(reportId).delete();
  }

  Future<void> deleteAllReports(String projectId) async {
    final collection = _reports(projectId);
    final snapshot = await collection.get();

    for (var i = 0; i < snapshot.docs.length; i += 450) {
      final batch = _firestore.batch();
      final end = (i + 450 < snapshot.docs.length)
          ? i + 450
          : snapshot.docs.length;

      for (final doc in snapshot.docs.sublist(i, end)) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    }
  }
}
