import 'syscall_ffi.dart' if (dart.library.js_interop) 'syscall_web.dart';

/// A point-in-time snapshot of the filesystem that contains a given path.
///
/// All three values are read from a single OS call, so they are mutually
/// consistent with each other. Every value is in bytes.
///
/// Beware: [freeBytes] + [usedBytes] may be *less* than [totalBytes]. The
/// difference is space that exists but that you cannot write — root-reserved
/// blocks on Linux, and sibling volumes sharing an APFS container on macOS.
class DiskSpaceInfo {
  /// Total size of the filesystem holding the queried path.
  ///
  /// On Windows this is quota-aware: if the user has a disk quota, this is the
  /// quota, not the physical volume size.
  final int totalBytes;

  /// Bytes that an unprivileged process may actually write.
  ///
  /// This is deliberately conservative and may under-report:
  /// * Linux/Android exclude blocks reserved for root (~5% on ext4).
  /// * Apple platforms exclude *purgeable* space — caches and offloadable
  ///   iCloud files the system would evict under write pressure. The real
  ///   figure can be 2x higher on a device with lots of free space, though the
  ///   two converge as the disk fills, which is when this number matters.
  /// * Windows respects per-user disk quotas.
  ///
  /// Treat it as a floor, never a guarantee: space can vanish between the
  /// query and the write.
  final int freeBytes;

  /// Bytes in use on the filesystem holding the queried path.
  ///
  /// Computed as `(total blocks - free blocks) x block size`, which matches
  /// `df`'s `Used` column on single-volume filesystems such as ext4, NTFS and
  /// HFS+.
  ///
  /// **On APFS it counts the whole container, not just your volume.** macOS
  /// puts the system, data, VM and preboot volumes in one shared container, and
  /// `statfs` reports container-level block counts, so this value is the sum
  /// across all of them. Measured on a 926 GiB container: this reports 850.7
  /// GiB used while `df` shows 811 GiB against `/System/Volumes/Data` alone,
  /// the balance being the sibling volumes. There is no API that yields
  /// per-volume usage here, so prefer [freeBytes] for decisions — it is
  /// container-level too, and container-level free space is what actually
  /// limits a write.
  final int usedBytes;

  /// Creates a snapshot from already-known values.
  ///
  /// Prefer [querySync] or [query]; this constructor exists for tests and for
  /// callers that persist and rehydrate a reading.
  const DiskSpaceInfo({required this.totalBytes, required this.freeBytes, required this.usedBytes});

  /// [usedBytes] as a fraction of [totalBytes], from 0.0 to 1.0.
  ///
  /// Returns 0.0 when [totalBytes] is 0, rather than NaN.
  double get usedFraction => totalBytes == 0 ? 0.0 : usedBytes / totalBytes;

  /// Whether [bytes] would fit in [freeBytes].
  ///
  /// Use [safetyFactor] when the peak on-disk cost exceeds the final size —
  /// extracting an archive needs room for both the archive and its contents,
  /// so pass 2.0:
  ///
  /// ```dart
  /// if (info.hasRoomFor(archiveBytes, safetyFactor: 2.0)) { ... }
  /// ```
  ///
  /// The requirement is `bytes * safetyFactor` rounded *up*, so a fractional
  /// factor never rounds in the caller's favour. Throws [ArgumentError] if
  /// [bytes] is negative or [safetyFactor] is not a finite positive number.
  bool hasRoomFor(int bytes, {double safetyFactor = 1.0}) {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be negative');
    }
    if (!safetyFactor.isFinite || safetyFactor <= 0) {
      throw ArgumentError.value(safetyFactor, 'safetyFactor', 'must be a finite positive number');
    }

    final double required = bytes * safetyFactor;
    if (required > freeBytes) {
      return false;
    }

    return required.ceil() <= freeBytes;
  }

  /// Queries the filesystem containing [path].
  ///
  /// [path] need not exist — the nearest existing ancestor directory is used,
  /// so you can ask about a file you are about to create. Relative paths are
  /// resolved against the current directory.
  ///
  /// Returns `null` when the answer cannot be determined: an unreadable path,
  /// an unsupported platform (web), or an OS-level failure. `null` means
  /// *unknown*, never zero — callers should proceed rather than block.
  ///
  /// Throws [ArgumentError] if [path] is empty.
  static DiskSpaceInfo? querySync(String path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }

    try {
      return queryNative(path);
    } on Object {
      return null;
    }
  }

  /// Asynchronous [querySync].
  ///
  /// The work is synchronous; this returns a [Future] for API stability and to
  /// suit `Future`-shaped call sites. No isolate is involved — the underlying
  /// call takes microseconds, so spawning one would cost more than the query.
  static Future<DiskSpaceInfo?> query(String path) async => querySync(path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiskSpaceInfo && other.totalBytes == totalBytes && other.freeBytes == freeBytes && other.usedBytes == usedBytes;

  @override
  int get hashCode => Object.hash(totalBytes, freeBytes, usedBytes);

  @override
  String toString() => 'DiskSpaceInfo(total: $totalBytes, free: $freeBytes, used: $usedBytes)';
}
