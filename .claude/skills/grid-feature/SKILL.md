---
name: grid-feature
description: Add a feature to the Lattice data grid across the engine and the Flutter adapter. Use when asked to add a column type, filter operator, aggregate, selection behaviour, export format or any other grid capability.
---

# Adding a grid feature

Work from the engine outwards. A feature that starts in a widget has to be
taken apart again before any other adapter can use it.

## 1. Place it

Ask which layer owns the behaviour:

| It is... | It belongs in |
| --- | --- |
| a rule about values, rows, ordering, matching or counting | `lattice_core` |
| a rule about what a gesture or key means | `lattice_core`, called by the adapter |
| a shape, colour, animation or layout | `packages/lattice_flutter` |

If the answer is "both", it is two changes, and the engine one lands first.

## 2. Engine change

1. Add the model, in the smallest form that expresses it. Prefer a value type
   with `==`, `hashCode` and `toJson` so saved views keep round-tripping.
2. Wire it through `GridQuery` if the data source needs to know, and through
   `GridController` as a method, so a toolbar button and a gesture take the
   same path.
3. If it changes what `InMemoryDataSource` computes, check the remote story
   too: `GridQuery.toJson` is a contract that server-backed grids translate.
4. Test it in `packages/lattice_core/test`, including the empty case, the
   single-row case, and the case where the data changes underneath it.

```bash
cd packages/lattice_core && dart analyze --fatal-infos && dart test
```

## 3. Adapter change

Only once the engine part is green:

1. Render the new state; call the new controller method from the gesture.
2. Keep view-only state (hover, scroll, text editing) in the widget, and
   nothing else.
3. Add a widget test that proves the wiring, not the behaviour — the engine
   tests already own the behaviour.

```bash
cd packages/lattice_flutter && flutter analyze && flutter test
```

If there is no Flutter SDK on this machine, say so rather than implying the
widget layer was verified locally; CI compiles it.

## 4. Document it

- `///` doc comments on anything exported, including the rule behind it.
- A row in the feature table of the relevant `README.md`.
- A `CHANGELOG.md` entry under an `## Unreleased` heading.

## 5. Ship it

One feature, one pull request, following `CONTRIBUTING.md`. Say in the PR
which decisions were judgement calls — those are what a reviewer should spend
their attention on.
