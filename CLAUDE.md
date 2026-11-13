# Working in this repository

Lattice is an open source data grid. `packages/lattice_core` is the engine in
pure Dart; `packages/lattice_flutter` is the Flutter adapter over it. Adapters
for other frameworks are planned and are the reason the engine is separate.

## The rule that matters most

**Behaviour goes in `lattice_core`. Only painting and gestures go in an
adapter.**

If you are about to put a comparator, a filter decision, a selection rule, a
page calculation or an expansion toggle inside a widget, stop: it belongs in
the engine, where it can be unit tested without pumping a frame, and where
every other adapter gets it for free.

An adapter may do three things:

1. read controller state and render it,
2. translate a gesture or key into a controller method call,
3. hold view-only state the engine has no opinion about (hover, scroll
   offsets, an editor's `TextEditingController`).

Anything else is a design error, however convenient.

## Before you say something works

`lattice_core` runs locally:

```bash
cd packages/lattice_core
dart pub get
dart analyze --fatal-infos
dart test
dart format --output=none --set-exit-if-changed .
dart example/lattice_core_example.dart   # end-to-end smoke test, no Flutter needed
```

`lattice_flutter` needs the Flutter SDK:

```bash
cd packages/lattice_flutter
flutter pub get
flutter analyze
flutter test
```

If the Flutter SDK is not installed on this machine, say so plainly rather
than claiming the widget layer is verified. `dart format` still works without
it, and CI is the compiler of record. **Do not claim a check passed that you
did not run.**

CI runs all of the above on every pull request, including
`dart analyze --fatal-infos`, so an `info`-level lint fails the build.

## Conventions

- **Dart style.** `dart format` decides layout; do not hand-wrap against it.
  Note that the formatter moves `// ignore:` comments when it rewraps a
  literal, which silently breaks the ignore — prefer restructuring the code
  over an ignore comment.
- **Comments explain why.** The code already says what it does. A comment
  earns its place by recording a decision, a trade-off or a trap, not by
  narrating the next line.
- **Public API carries doc comments.** Every exported member gets `///`, and
  anything with a non-obvious rule says what the rule is.
- **Nulls.** Prefer making the invalid state unrepresentable. Where null is
  meaningful, say what it means in the doc comment.
- **No new dependencies in `lattice_core`.** It is pure Dart on purpose. The
  adapter may depend on Flutter and nothing else.
- Generic type parameters are `T` for the row type throughout.

## Tests

Every behavioural change needs a test, and the test goes at the lowest layer
that can express it — engine tests over widget tests, almost always.

Name tests as a sentence about behaviour, not about the method:

```dart
test('places nulls last in both directions by default', ...)   // yes
test('sortRows works', ...)                                     // no
```

Cover the edge first. The bugs in a grid live in empty data, a single row, a
filter that matches nothing, a column that was hidden while selected, a page
past the end, and a response that arrives after a newer one.

## Commits and pull requests

- One concern per pull request. A PR that adds a feature and reformats
  unrelated files is two PRs.
- Commit messages: imperative subject under ~72 characters, then a body that
  explains **why** if it is not obvious. No trailers, no attribution lines.
- Keep commits small and self-contained; a reviewer should be able to read
  them in order.
- Fill in the pull request template honestly, including what you did not test.

## Performance

The engine is expected to handle 10k–50k rows interactively. Before claiming a
speed-up, measure it:

```bash
cd packages/lattice_core
dart run benchmark/grid_benchmark.dart
```

Report before and after numbers in the PR. "Should be faster" is not a result.

## Security

Never add code that reads the network, the filesystem or environment
variables to `lattice_core` — it is a pure computation library and must stay
that way, so that auditing it is tractable. See `SECURITY.md`.
