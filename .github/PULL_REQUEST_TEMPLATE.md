## What this changes

<!-- One or two sentences. What is different after this PR that was not before? -->

## Why

<!-- The problem, not the patch. If it fixes an issue, "Fixes #123". -->

## Decisions worth a reviewer's attention

<!--
Where did you have to choose? A default, a name, a trade-off, something you
are unsure about. This is the most useful section in the template - reviewers
have limited attention and this is where to spend it.
-->

## Layering

- [ ] Grid behaviour went in `lattice_core`, not in a widget
- [ ] The adapter only renders state and forwards gestures

<!-- If you broke this rule on purpose, say why here instead of ticking it. -->

## Testing

- [ ] `dart analyze --fatal-infos` and `dart test` pass for `lattice_core`
- [ ] `flutter analyze` and `flutter test` pass for `lattice_flutter`
- [ ] `dart format` leaves no changes
- [ ] New behaviour has tests at the lowest layer that can express it

**What I did not test:**

<!--
Be specific and honest. "No Flutter SDK locally, so the widget layer is only
verified by CI" is a useful thing for a reviewer to know. An empty answer
here reads as "nothing", which had better be true.
-->

## Performance

<!--
Only if this touches the pipeline, layout or virtualization. Numbers from
`dart run benchmark/grid_benchmark.dart`, before and after. Delete this
section if it does not apply - do not leave a guess in it.
-->

## Breaking changes

<!--
Any rename, default change, or behaviour a consumer could be relying on.
Say what a user has to do to upgrade. Write "None" if there are none.
-->
