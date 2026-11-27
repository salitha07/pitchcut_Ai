import 'package:material_ui/material_ui.dart';

import '../../../models/caption.dart';

/// Shows the caption that is active at [positionMs], or nothing.
class CaptionOverlay extends StatelessWidget {
  const CaptionOverlay({
    super.key,
    required this.captions,
    required this.positionMs,
  });

  final List<Caption> captions;
  final int positionMs;

  Caption? _active() {
    for (final c in captions) {
      if (positionMs >= c.startMs && positionMs < c.endMs) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final caption = _active();
    if (caption == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        caption.text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}
