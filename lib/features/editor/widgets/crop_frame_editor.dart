import 'package:flutter/material.dart';

import '../models/crop_rect.dart';

/// Drag inside the frame to move it; drag a corner or edge to resize it.
class CropFrameEditor extends StatefulWidget {
  const CropFrameEditor({
    super.key,
    required this.crop,
    required this.onChanged,
  });

  final CropRect crop;
  final ValueChanged<CropRect> onChanged;

  @override
  State<CropFrameEditor> createState() => _CropFrameEditorState();
}

class _CropFrameEditorState extends State<CropFrameEditor> {
  static const _handleRadius = 0.07;
  CropRect? _startCrop;
  Offset? _startPoint;
  Set<String> _edges = {};

  void _start(DragStartDetails details, Size size) {
    _startCrop = widget.crop;
    _startPoint = Offset(
      details.localPosition.dx / size.width,
      details.localPosition.dy / size.height,
    );
    final point = _startPoint!;
    final crop = widget.crop;
    _edges = {
      if ((point.dx - crop.left).abs() < _handleRadius) 'left',
      if ((point.dx - crop.right).abs() < _handleRadius) 'right',
      if ((point.dy - crop.top).abs() < _handleRadius) 'top',
      if ((point.dy - crop.bottom).abs() < _handleRadius) 'bottom',
    };
  }

  void _update(DragUpdateDetails details, Size size) {
    final start = _startCrop;
    final point = _startPoint;
    if (start == null || point == null) return;
    final delta = Offset(
      details.localPosition.dx / size.width - point.dx,
      details.localPosition.dy / size.height - point.dy,
    );
    if (_edges.isEmpty) {
      widget.onChanged(start.move(delta.dx, delta.dy));
    } else {
      widget.onChanged(
        start.resize(
          left: _edges.contains('left') ? start.left + delta.dx : null,
          right: _edges.contains('right') ? start.right + delta.dx : null,
          top: _edges.contains('top') ? start.top + delta.dy : null,
          bottom: _edges.contains('bottom') ? start.bottom + delta.dy : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _start(details, size),
        onPanUpdate: (details) => _update(details, size),
        child: CustomPaint(
          painter: _CropFramePainter(widget.crop),
          size: Size.infinite,
        ),
      );
    },
  );
}

class _CropFramePainter extends CustomPainter {
  const _CropFramePainter(this.crop);
  final CropRect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect),
      shade,
    );
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);
    final handle = Paint()..color = Colors.white;
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(point, 6, handle);
    }
  }

  @override
  bool shouldRepaint(_CropFramePainter oldDelegate) => oldDelegate.crop != crop;
}
