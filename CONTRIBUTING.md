# Contributing

Contributions are welcome, including small ones. This file is short on purpose:
the conventions that matter are in [CLAUDE.md](CLAUDE.md), which applies to
humans and agents alike.

## Getting set up

```bash
git clone https://github.com/Dhairya-007/lattice.git
cd lattice

cd packages/lattice_core && dart pub get
dart test
dart example/lattice_core_example.dart   # end-to-end, no Flutter required

cd ../lattice_flutter && flutter pub get
flutter test
cd example && flutter run
```

The engine needs only the Dart SDK, so you can work on grid behaviour without
a Flutter install.

## The one architectural rule

**Behaviour lives in `lattice_core`; the Flutter package only paints and
listens.** Sorting, filtering, grouping, selection, paging and editing rules
all belong in the engine, where they are unit tested and where future adapters
inherit them. A widget that decides any of those is a bug waiting to be ported.

## Before opening a pull request

```bash
cd packages/lattice_core
dart analyze --fatal-infos && dart test && dart format --output=none --set-exit-if-changed .

cd ../lattice_flutter
flutter analyze && flutter test && dart format --output=none --set-exit-if-changed .
```

CI runs exactly this. Note `--fatal-infos`: an info-level lint fails the build.

## Pull requests

- **One concern per PR.** Adding a feature and reformatting unrelated files is
  two pull requests.
- **Tests at the lowest layer that can express the behaviour** — an engine test
  beats a widget test nearly every time.
- **Fill in the template honestly**, including what you did not test. Saying
  "no Flutter SDK locally, CI is the only compiler here" is useful; implying a
  check passed that you never ran is not.
- **Say where you had to make a judgement call.** That is where review
  attention is worth spending.

Commit messages: imperative subject under ~72 characters, and a body that
explains why when it is not obvious.

## Reporting bugs

Use the issue template, and narrow it as far as you can. If you can turn it
into a failing `lattice_core` test, you have done most of the work of fixing
it.

Security issues go through
[the private advisory form](https://github.com/Dhairya-007/lattice/security/advisories/new)
instead — see [SECURITY.md](SECURITY.md).

## Scope

Lattice aims to be a complete data grid, so most grid features are in scope.
Two things are not:

- **Anything that makes `lattice_core` depend on a UI toolkit**, or on the
  network, filesystem or environment.
- **Features that only work on one platform**, unless they degrade cleanly
  everywhere else.

If you are unsure whether something fits, open an issue before writing it.
