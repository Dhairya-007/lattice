/// Versioning for everything the engine serialises.
library;

/// The schema version this build writes.
///
/// A saved view or a stored query is a user's work, kept outside the app and
/// read back by a later version of it. Stamping the format means a format
/// change can be migrated rather than silently misread - and that "their
/// saved layouts stopped working" is a thing that cannot happen quietly.
const int latticeSchemaVersion = 1;

/// Key the version is stored under. Short, because it appears in every
/// document.
const String latticeSchemaVersionKey = 'v';

/// Reads and checks the version of a serialised [what].
///
/// A document with no version is treated as version 1: documents written
/// before versioning existed are valid version 1 documents, and refusing
/// them would break exactly the saved layouts this is meant to protect.
///
/// Throws [FormatException] for a version this build does not understand,
/// which is a newer one. Failing loudly is the point: silently reading a
/// future format produces a grid arranged some way nobody asked for.
int requireSupportedSchema(Map<String, Object?> json, {required String what}) {
  final raw = json[latticeSchemaVersionKey];
  if (raw == null) return 1;
  final version = raw is int ? raw : int.tryParse('$raw');
  if (version == null) {
    throw FormatException('$what has a malformed schema version: $raw');
  }
  if (version > latticeSchemaVersion) {
    throw FormatException(
      '$what was written by a newer version of Lattice (schema v$version; '
      'this build understands up to v$latticeSchemaVersion).',
    );
  }
  return version;
}
