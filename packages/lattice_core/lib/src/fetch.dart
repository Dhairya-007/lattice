/// Cooperative cancellation for in-flight fetches.
library;

import 'dart:async';

/// Thrown by a data source that notices its fetch was cancelled.
///
/// The grid swallows it: a cancelled request has no answer to show and is not
/// a failure the user should see. Anything else a source throws becomes
/// `GridController.error`.
class FetchCancelled implements Exception {
  const FetchCancelled([this.reason]);

  /// Why the fetch was cancelled, if the caller said.
  final String? reason;

  @override
  String toString() =>
      reason == null ? 'FetchCancelled' : 'FetchCancelled: $reason';
}

/// Tells a data source that the grid no longer wants the answer.
///
/// The grid already drops a stale response, so a result that arrives late can
/// never overwrite a newer one - but dropping it is not the same as not
/// paying for it. Every keystroke in a filter row starts a request that runs
/// to completion on the server, holds a connection and burns quota. A source
/// that is handed one of these can abort instead: pass [isCancelled] to an
/// HTTP client's abort flag, register [onCancel] to close a socket, or call
/// [throwIfCancelled] between the stages of a long local computation.
///
/// Cancellation is cooperative. A source that ignores the signal is still
/// correct, just wasteful.
class FetchSignal {
  FetchSignal();

  bool _cancelled = false;
  String? _reason;
  List<void Function()>? _listeners;
  Completer<void>? _completer;

  /// Whether the grid has given up on this fetch.
  bool get isCancelled => _cancelled;

  /// Why, if a reason was given.
  String? get reason => _reason;

  /// Completes when the fetch is cancelled, for a source that would rather
  /// race than poll: `await Future.any([request, signal.whenCancelled])`.
  Future<void> get whenCancelled {
    final completer = _completer ??= Completer<void>();
    if (_cancelled && !completer.isCompleted) completer.complete();
    return completer.future;
  }

  /// Runs [listener] when the fetch is cancelled, or immediately if it already
  /// has been.
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    (_listeners ??= <void Function()>[]).add(listener);
  }

  /// Throws [FetchCancelled] if the fetch has been cancelled.
  ///
  /// The cheapest way for a source to bail out part-way through work it is
  /// doing itself.
  void throwIfCancelled() {
    if (_cancelled) throw FetchCancelled(_reason);
  }

  /// Cancels the fetch. Called by the grid, which owns the signal; calling it
  /// twice does nothing.
  void cancel([String? reason]) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    final listeners = _listeners;
    _listeners = null;
    if (listeners != null) {
      for (final listener in listeners) {
        listener();
      }
    }
    final completer = _completer;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}
