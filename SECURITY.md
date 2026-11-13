# Security policy

## Reporting a vulnerability

Report privately through
[GitHub's security advisory form](https://github.com/Dhairya-007/lattice/security/advisories/new).
Please do not open a public issue for a vulnerability.

Include what you can: the affected package and version, what an attacker can
achieve, and a reproduction. A failing test is the fastest possible path to a
fix.

Expect an acknowledgement within 5 days and an assessment within 14. If a fix
is warranted it ships as a patch release with an advisory crediting you, unless
you would rather not be named.

## Supported versions

While Lattice is pre-1.0, only the latest minor version of each package
receives fixes. Published versions are never deleted, only retracted, so a
fixed vulnerability means upgrading rather than waiting for a patched old
version.

## What is in scope

A data grid is a rendering and computation library, so the realistic risks are
narrow and worth stating:

- **Denial of service through pathological input** — data or a query that
  makes the pipeline take unbounded time or memory. Quadratic or worse
  behaviour reachable from untrusted data is a vulnerability, not just a
  performance bug.
- **Unsafe handling of a value during export.** CSV in particular: a cell
  beginning `=`, `+`, `-` or `@` is executed as a formula when the file is
  opened in a spreadsheet, which turns exported user data into
  [CSV injection](https://owasp.org/www-community/attacks/CSV_Injection).
  Mitigation belongs in the exporter, not in every consumer.
- **Leaking values across a trust boundary** — a filter, group label, tooltip
  or clipboard payload that exposes data from a column the user was not meant
  to see.
- **Supply chain** — an unexpected dependency, or a dependency with a known
  advisory, reaching either package.

## What is not in scope

- Authorisation. The grid renders the rows it is given; deciding which rows a
  user may see is the application's job, and no grid can do it for you.
- Anything requiring the attacker to already control the host application's
  Dart code.
- Vulnerabilities in the Flutter SDK itself — report those to Flutter.

## How this project reduces its own attack surface

- **`lattice_core` has no runtime dependencies at all**, and must not acquire
  any: no network, no filesystem, no environment access, no platform channels.
  It is pure computation, which keeps auditing it tractable. `lattice_flutter`
  depends only on Flutter and the engine.
- Dependency updates arrive as Dependabot pull requests, and every pull request
  runs an OSV scan of the resolved dependency versions. GitHub's dependency
  review needs the repository's dependency graph enabled in settings; OSV
  covers the same ground without it.
- Publishing to pub.dev goes through GitHub OIDC, so no long-lived publishing
  token exists in this repository or on a maintainer's machine.
- Workflows are pinned to major versions of first-party actions and run with
  read-only permissions except where publishing explicitly needs otherwise.
