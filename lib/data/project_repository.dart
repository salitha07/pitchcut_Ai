import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/project.dart';
import '../models/clip.dart';

class ProjectRepository {
  ProjectRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please log in to manage projects.');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _projects =>
      _firestore.collection('users').doc(_userId).collection('projects');

  // Create a project
  Future<void> createProject(Project project) async {
    final doc = _projects.doc(project.id);

    await doc.set({...project.toJson(), 'userId': _userId});
  }

  // Get all projects belonging to the signed-in user
  Future<List<Project>> getProjects() async {
    final snapshot = await _projects.get();

    return snapshot.docs.map((doc) {
      return Project.fromJson(doc.data());
    }).toList();
  }

  // Listen for project changes in real time
  Stream<List<Project>> watchProjects() {
    return _projects.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Project.fromJson(doc.data());
      }).toList();
    });
  }

  // Update a project
  Future<void> updateProject(Project project) async {
    if (project.userId != _userId) {
      throw StateError('You cannot update another user\'s project.');
    }

    await _projects.doc(project.id).update(project.toJson());
  }

  // Delete a project and its stored clip documents
  Future<void> deleteProject(String projectId) async {
    final projectRef = _projects.doc(projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      return;
    }

    final clips = projectRef.collection('clips');
    final clipSnapshot = await clips.get();

    final batch = _firestore.batch();

    for (final clip in clipSnapshot.docs) {
      batch.delete(clip.reference);
    }

    batch.delete(projectRef);
    await batch.commit();
  }

  // Add a clip to a project
  Future<void> addClip(Clip clip) async {
    final projectRef = _projects.doc(clip.projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    final clipRef = projectRef.collection('clips').doc(clip.id);

    final batch = _firestore.batch();

    batch.set(clipRef, clip.toJson());

    batch.update(projectRef, {
      'clipIds': FieldValue.arrayUnion([clip.id]),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    await batch.commit();
  }

  // Get clips for a project
  Future<List<Clip>> getClips(String projectId) async {
    final projectRef = _projects.doc(projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    final snapshot = await projectRef.collection('clips').get();

    return snapshot.docs.map((doc) {
      return Clip.fromJson(doc.data());
    }).toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  // Update a clip
  Future<void> updateClip(Clip clip) async {
    final projectRef = _projects.doc(clip.projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    await projectRef.collection('clips').doc(clip.id).update(clip.toJson());
  }

  // Delete a clip
  Future<void> deleteClip(String projectId, String clipId) async {
    final projectRef = _projects.doc(projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    final batch = _firestore.batch();

    batch.delete(projectRef.collection('clips').doc(clipId));

    batch.update(projectRef, {
      'clipIds': FieldValue.arrayRemove([clipId]),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    await batch.commit();
  }
}
