import 'package:flutter/widgets.dart';

/// Keeps several scroll views locked to one offset.
///
/// Frozen columns mean the grid has more than one scrollable along the same
/// axis: the pinned panes and the scrolling pane each have their own vertical
/// view, and the header scrolls horizontally with the body. A single
/// [ScrollController] cannot drive several attached views, so each view gets
/// its own controller and this group mirrors whichever one the user is
/// actually dragging onto the others.
///
/// All members must have the same scrollable extent along the shared axis,
/// which holds here: the panes render the same rows at the same heights, and
/// the header is exactly as wide as the body.
class SyncedScrollGroup {
  SyncedScrollGroup({double initialOffset = 0}) : _offset = initialOffset;

  final List<ScrollController> _controllers = [];
  final Map<ScrollController, VoidCallback> _listeners = {};

  double _offset;

  /// Guards against the mirrored jumps notifying their way back round.
  bool _syncing = false;

  /// The shared offset.
  double get offset => _offset;

  /// Creates a controller that is part of this group.
  ScrollController addAndGet() {
    final controller = ScrollController(initialScrollOffset: _offset);
    void listener() => _onChanged(controller);
    controller.addListener(listener);
    _listeners[controller] = listener;
    _controllers.add(controller);
    return controller;
  }

  void _onChanged(ScrollController source) {
    if (_syncing || !source.hasClients) return;
    final next = source.offset;
    if (next == _offset) return;
    _offset = next;
    _syncing = true;
    try {
      for (final other in _controllers) {
        if (other == source || !other.hasClients) continue;
        // Clamp to the other view's own range: a pane can be a fraction of a
        // pixel shorter mid-layout, and jumping out of range throws.
        final position = other.position;
        final target = next.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (other.offset != target) other.jumpTo(target);
      }
    } finally {
      _syncing = false;
    }
  }

  /// Jumps every member to [offset].
  void jumpTo(double offset) {
    _offset = offset;
    _syncing = true;
    try {
      for (final controller in _controllers) {
        if (!controller.hasClients) continue;
        final position = controller.position;
        controller.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
    } finally {
      _syncing = false;
    }
  }

  /// Animates every member to [offset].
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    final targets = [
      for (final controller in _controllers)
        if (controller.hasClients) controller,
    ];
    if (targets.isEmpty) {
      _offset = offset;
      return;
    }
    _offset = offset;
    _syncing = true;
    try {
      await Future.wait([
        for (final controller in targets)
          controller.animateTo(
            offset.clamp(
              controller.position.minScrollExtent,
              controller.position.maxScrollExtent,
            ),
            duration: duration,
            curve: curve,
          ),
      ]);
    } finally {
      _syncing = false;
    }
  }

  /// Largest offset any member can reach.
  double get maxScrollExtent {
    var max = 0.0;
    for (final controller in _controllers) {
      if (!controller.hasClients) continue;
      final extent = controller.position.maxScrollExtent;
      if (extent > max) max = extent;
    }
    return max;
  }

  /// Extent of the viewport, from whichever member is attached.
  double get viewportExtent {
    for (final controller in _controllers) {
      if (controller.hasClients) return controller.position.viewportDimension;
    }
    return 0;
  }

  void dispose() {
    for (final controller in _controllers) {
      final listener = _listeners[controller];
      if (listener != null) controller.removeListener(listener);
      controller.dispose();
    }
    _controllers.clear();
    _listeners.clear();
  }
}
