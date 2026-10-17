import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/clip.dart';
import '../models/project.dart';
import 'storage_repository.dart';

class ProjectRepository {
  ProjectRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this._storageRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final StorageRepository? _storageRepository;

  // Get the signed-in user's ID.
  String get _userId {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please log in to manage projects.');
    }

    return user.uid;
  }

  // Get the signed-in user's projects collection.
  CollectionReference<Map<String, dynamic>> get _projects =>
      _firestore.collection('users').doc(_userId).collection('projects');

  // Create a project.
  Future<void> createProject(Project project) async {
    final doc = _projects.doc(project.id);

    await doc.set({...project.toJson(), 'userId': _userId});
  }

  // Get all projects belonging to the signed-in user.
  Future<List<Project>> getProjects() async {
    final snapshot = await _projects.get();

    return snapshot.docs.map((doc) {
      return Project.fromJson(doc.data());
    }).toList();
  }

  // Listen for project changes in real time.
  Stream<List<Project>> watchProjects() {
    return _projects.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Project.fromJson(doc.data());
      }).toList();
    });
  }

  // Update a project owned by the signed-in user.
  Future<void> updateProject(Project project) async {
    if (project.userId != _userId) {
      throw StateError('You cannot update another user\'s project.');
    }

    await _projects.doc(project.id).update({
      ...project.toJson(),
      'userId': _userId,
    });
  }

  // Delete every document in a collection in batches.
  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(400).get();

      if (snapshot.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();

      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }

      await batch.commit();
    }
  }

  // Delete a project, its Firestore subcollections, and Storage files.
  Future<void> deleteProject(String projectId) async {
    final projectRef = _projects.doc(projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      return;
    }

    // Delete files first when StorageRepository is provided.
    final storageRepository = _storageRepository;

    if (storageRepository != null) {
      await storageRepository.deleteProjectFiles(projectId);
    }

    // Delete Firestore subcollections.
    await _deleteCollection(projectRef.collection('clips'));
    await _deleteCollection(projectRef.collection('captions'));
    await _deleteCollection(projectRef.collection('reports'));

    // Delete the project document last.
    await projectRef.delete();
  }

  // Add a clip to an existing project.
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

  // Get clips for a project, sorted by order.
  Future<List<Clip>> getClips(String projectId) async {
    final projectRef = _projects.doc(projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    final snapshot = await projectRef.collection('clips').get();

    final clips = snapshot.docs.map((doc) {
      return Clip.fromJson(doc.data());
    }).toList();

    clips.sort((a, b) => a.order.compareTo(b.order));

    return clips;
  }

  // Update an existing clip.
  Future<void> updateClip(Clip clip) async {
    final projectRef = _projects.doc(clip.projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    await projectRef.collection('clips').doc(clip.id).update(clip.toJson());

    await projectRef.update({
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Delete a clip and remove its ID from the project.
  Future<void> deleteClip(String projectId, String clipId) async {
    final projectRef = _projects.doc(projectId);
    final projectSnapshot = await projectRef.get();

    if (!projectSnapshot.exists) {
      throw StateError('Project not found.');
    }

    final clipRef = projectRef.collection('clips').doc(clipId);
    final clipSnapshot = await clipRef.get();

    if (!clipSnapshot.exists) {
      return;
    }

    // Delete the associated Storage video if Storage is connected.
    final storageRepository = _storageRepository;

    if (storageRepository != null) {
      await storageRepository.deleteVideo(projectId: projectId, clipId: clipId);
    }

    final batch = _firestore.batch();

    batch.delete(clipRef);

    batch.update(projectRef, {
      'clipIds': FieldValue.arrayRemove([clipId]),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    await batch.commit();
  }
}
