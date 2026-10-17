import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/caption.dart';

class CaptionRepository {
  CaptionRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please log in to manage captions.');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> _captions(String projectId) {
    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('projects')
        .doc(projectId)
        .collection('captions');
  }

  Future<void> saveCaption(String projectId, Caption caption) async {
    await _captions(projectId).doc(caption.id).set(caption.toJson());
  }

  Future<void> saveCaptions(String projectId, List<Caption> captions) async {
    final collection = _captions(projectId);
    final batch = _firestore.batch();

    for (final caption in captions) {
      batch.set(collection.doc(caption.id), caption.toJson());
    }

    if (captions.isNotEmpty) {
      await batch.commit();
    }
  }

  Future<List<Caption>> getCaptions(String projectId) async {
    final snapshot = await _captions(projectId).get();

    final captions = snapshot.docs
        .map((doc) => Caption.fromJson(doc.data()))
        .toList();

    captions.sort((a, b) => a.startMs.compareTo(b.startMs));
    return captions;
  }

  Stream<List<Caption>> watchCaptions(String projectId) {
    return _captions(projectId).snapshots().map((snapshot) {
      final captions = snapshot.docs
          .map((doc) => Caption.fromJson(doc.data()))
          .toList();

      captions.sort((a, b) => a.startMs.compareTo(b.startMs));
      return captions;
    });
  }

  Future<void> updateCaption(String projectId, Caption caption) async {
    await _captions(projectId).doc(caption.id).update(caption.toJson());
  }

  Future<void> deleteCaption(String projectId, String captionId) async {
    await _captions(projectId).doc(captionId).delete();
  }

  Future<void> deleteAllCaptions(String projectId) async {
    final collection = _captions(projectId);
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
