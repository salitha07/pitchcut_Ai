
import 'package:material_ui/material_ui.dart';

import '../../../models/caption.dart';

/// Opens a dialog to add or edit a caption.
/// Returns the new or updated [Caption], or null if cancelled.
Future<Caption?> showCaptionEditDialog(
  BuildContext context, {
  Caption? existing,
}) {
  return showDialog<Caption>(
    context: context,
    builder: (_) => _CaptionEditDialog(existing: existing),
  );
}

class _CaptionEditDialog extends StatefulWidget {
  const _CaptionEditDialog({this.existing});

  final Caption? existing;

  @override
  State<_CaptionEditDialog> createState() => _CaptionEditDialogState();
}

class _CaptionEditDialogState extends State<_CaptionEditDialog> {
  late final TextEditingController _text;
  late final TextEditingController _start;
  late final TextEditingController _end;

  String? _error;

  @override
  void initState() {
    super.initState();

    final caption = widget.existing;

    _text = TextEditingController(text: caption?.text ?? '');

    _start = TextEditingController(
      text: ((caption?.startMs ?? 0) / 1000).toStringAsFixed(1),
    );

    _end = TextEditingController(
      text: ((caption?.endMs ?? 2000) / 1000).toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _save() {
    final text = _text.text.trim();
    final startSec = double.tryParse(_start.text.trim());
    final endSec = double.tryParse(_end.text.trim());

    if (text.isEmpty) {
      setState(() => _error = 'Caption text cannot be empty.');
      return;
    }

    if (startSec == null || endSec == null) {
      setState(
        () => _error = 'Start and end must be numbers (seconds).',
      );
      return;
    }

    if (!startSec.isFinite || !endSec.isFinite) {
      setState(() => _error = 'Please enter valid time values.');
      return;
    }

    final startMs = (startSec * 1000).round();
    final endMs = (endSec * 1000).round();

    if (startMs < 0 || endMs <= startMs) {
      setState(
        () => _error = 'End time must be greater than start time.',
      );
      return;
    }

    final existing = widget.existing;

    // Keep the original source timestamp aligned with timeline edits.
    final sourceStartMs = existing?.sourceStartMs == null
        ? null
        : existing!.sourceStartMs! + (startMs - existing.startMs);

    Navigator.of(context).pop(
      Caption(
        id: existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        startMs: startMs,
        endMs: endMs,
        text: text,
        sourceClipId: existing?.sourceClipId,
        sourceStartMs: sourceStartMs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add caption' : 'Edit caption',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _text,
              decoration: const InputDecoration(labelText: 'Text'),
              maxLines: 3,
            ),
            TextField(
              controller: _start,
              decoration: const InputDecoration(
                labelText: 'Start (seconds)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextField(
              controller: _end,
              decoration: const InputDecoration(
                labelText: 'End (seconds)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
