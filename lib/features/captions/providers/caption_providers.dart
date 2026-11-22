import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/caption.dart';
import '../../../providers/repository_providers.dart';

/// Live list of captions for one project, sorted by startMs.
final captionsProvider = StreamProvider.family<List<Caption>, String>((
  ref,
  projectId,
) {
  return ref.watch(captionRepositoryProvider).watchCaptions(projectId);
});
