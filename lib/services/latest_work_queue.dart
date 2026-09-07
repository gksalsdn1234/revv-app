/// At most one active operation and one pending (latest) state.
class LatestWorkQueue<T> {
  T? _pending;
  Future<void>? _running;
  Future<void> submit(T value, Future<void> Function(T) work) {
    _pending = value;
    return _running ??= _drain(work).whenComplete(() => _running = null);
  }

  Future<void> _drain(Future<void> Function(T) work) async {
    while (_pending != null) {
      final value = _pending as T;
      _pending = null;
      await work(value);
    }
  }
}

/// Source/layer creation occurs once per style; updates retain the layers.
class RetainedRouteSources {
  final Map<String, String> _data = {};
  int _generation = 0;
  void reset() {
    _generation++;
    _data.clear();
  }

  bool contains(String id) => _data.containsKey(id);
  Future<void> put(
    String id,
    String data, {
    required Future<void> Function() create,
    required Future<void> Function() update,
  }) async {
    if (_data[id] == data) return;
    final generation = _generation;
    if (_data.containsKey(id)) {
      await update();
    } else {
      await create();
    }
    if (generation == _generation) _data[id] = data;
  }
}
