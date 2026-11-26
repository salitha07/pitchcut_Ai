class EditorCommandHistory<T> {
  final List<({T before, T after})> _undoStack = [];
  final List<({T before, T after})> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void record({required T before, required T after}) {
    _undoStack.add((before: before, after: after));
    _redoStack.clear();
  }

  T? undo() {
    if (_undoStack.isEmpty) return null;
    final command = _undoStack.removeLast();
    _redoStack.add(command);
    return command.before;
  }

  T? redo() {
    if (_redoStack.isEmpty) return null;
    final command = _redoStack.removeLast();
    _undoStack.add(command);
    return command.after;
  }
}
