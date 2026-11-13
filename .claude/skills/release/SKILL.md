---
name: release
description: Cut and publish a release of lattice_core or lattice_flutter to pub.dev. Use when asked to release, publish, bump a version, or tag a package in this repository.
---

# Releasing a Lattice package

Two packages release independently. `lattice_flutter` depends on
`lattice_core`, so core always goes first.

## 1. Decide the version

Semver, judged from the public API:

- **patch** — a fix with no API change.
- **minor** — new API, existing API untouched.
- **major** (or a `0.x` bump) — anything a consumer must change code for,
  including a rename, a default change, or a behavioural change they could be
  relying on.

Renaming an exported member is breaking even when the old name was wrong.

## 2. Prepare

```bash
cd packages/<package>
dart pub get
dart analyze --fatal-infos && dart test        # core
flutter analyze && flutter test                # flutter
dart format --output=none --set-exit-if-changed .
```

Update, in the package directory:

- `pubspec.yaml` — the `version:` field.
- `CHANGELOG.md` — a new section for this version, written for a reader
  deciding whether to upgrade. Lead with breaking changes.

For `lattice_flutter` only: its dependency on `lattice_core` is a `path:`
dependency during development and pub.dev refuses to publish that. Switch it
to the hosted constraint for the release commit:

```yaml
dependencies:
  lattice_core: ^<the version just published>
```

## 3. Validate exactly what pub.dev will see

```bash
dart pub publish --dry-run
```

It must report no errors. Common ones:

- **missing LICENSE** — each package needs its own copy in its own root; a
  licence at the repository root does not count.
- **modified files in git** — commit first, publish from a clean tree.
- **`example/` missing** — pub.dev scores it.

## 4. Publish

The **first ever** publish of a package has to be done by hand, because it is
what claims the name, and it needs an interactive browser sign-in:

```bash
dart pub publish
```

After that, publishing is automated. Tag and push:

```bash
git tag lattice_core-v0.2.0
git push origin lattice_core-v0.2.0
```

`.github/workflows/publish.yml` publishes via OIDC, with no stored token.
It requires *Automated publishing* to be enabled on the package's pub.dev
admin page, pointed at this repository with a matching tag pattern.

## 5. Afterwards

- Check the package's pub.dev score and fix anything it flags.
- Restore the `path:` dependency in `lattice_flutter` for development, in a
  follow-up commit, so the monorepo keeps building against local core.
- A published version cannot be deleted, only retracted. If something is
  wrong, publish a fix as the next patch rather than trying to undo it.
