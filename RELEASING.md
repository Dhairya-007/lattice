# Releasing

Two packages, released independently. `lattice_flutter` depends on
`lattice_core`, so core always goes first.

## The one gotcha

During development `lattice_flutter` depends on the engine by path:

```yaml
dependencies:
  lattice_core:
    path: ../lattice_core
```

pub.dev refuses to publish a package with a path dependency, so the release
commit switches it to the published constraint:

```yaml
dependencies:
  lattice_core: ^0.1.0
```

Restore the path dependency in a follow-up commit, so the monorepo keeps
building against local core.

## Steps

1. Update `version:` in the package's `pubspec.yaml` and add a `CHANGELOG.md`
   section for it, leading with any breaking changes.
2. Run the full check: analyze, test and format, per
   [CONTRIBUTING.md](CONTRIBUTING.md).
3. `dart pub publish --dry-run` must report no errors. Each package needs its
   own `LICENSE` file in its own root — the repository-root licence does not
   count — and the tree must be clean.
4. The **first** publish of a package is manual, because it claims the name and
   needs an interactive browser sign-in:

   ```bash
   cd packages/lattice_core
   dart pub publish
   ```

5. Afterwards, releases are automated. Tag and push:

   ```bash
   git tag lattice_core-v0.2.0
   git push origin lattice_core-v0.2.0
   ```

   `.github/workflows/publish.yml` publishes through GitHub OIDC with no stored
   token. This requires *Automated publishing* to be enabled on the package's
   pub.dev admin page, pointing at this repository with a matching tag pattern.

## Versioning

Semver, judged by what a consumer has to change:

- **patch** — a fix, no API change.
- **minor** — new API, nothing existing touched.
- **major**, or a `0.x` bump while pre-1.0 — a rename, a changed default, or
  any behaviour someone could reasonably be relying on.

Renaming an exported member is breaking even when the old name was a mistake.

A published version cannot be deleted, only retracted. If a release is wrong,
publish the fix as the next patch rather than trying to undo it.
