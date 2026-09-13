import 'dart:io';

/// Resolves [path] to an absolute, existing directory suitable for a
/// filesystem-space query.
///
/// Every platform API used by this package fails on a path that does not exist,
/// so resolution happens once here rather than five times natively:
///
/// 1. The path is made absolute. This matters on Windows, where
///    `GetVolumePathNameW` silently reports the *boot* volume for a relative
///    path — a wrong answer rather than an error.
/// 2. The nearest existing ancestor directory is returned, so callers may ask
///    about a file they are about to create.
///
/// Returns `null` when nothing along the chain exists. Throws [ArgumentError]
/// if [path] is empty.
///
/// Caveat: the nearest existing ancestor may live on a different volume than
/// the final path eventually will (Windows mounted folders, Linux bind mounts,
/// an unmounted SD card).
String? resolveQueryDirectory(String path) {
  if (path.isEmpty) {
    throw ArgumentError.value(path, 'path', 'must not be empty');
  }

  Directory directory = Directory(path).absolute;

  while (true) {
    if (directory.existsSync()) {
      try {
        return directory.resolveSymbolicLinksSync();
      } on FileSystemException {
        return directory.path;
      }
    }

    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}
