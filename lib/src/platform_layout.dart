/// Byte offsets and widths of the filesystem-statistics struct for one
/// operating system and architecture.
///
/// Fields are read by offset rather than through a `Struct` subclass so that a
/// mistake here produces a wrong number, never an out-of-bounds read.
class FsLayout {
  /// The libc symbol to call, `statfs` on Darwin and `statvfs` elsewhere.
  ///
  /// This is the *logical* name, and the one [checkLayout] compares against the
  /// struct in the system headers. The symbol actually exported by libc may
  /// differ per architecture — see [lookupSymbols].
  final String symbol;

  /// Symbols to look up, in order of preference, until one resolves.
  ///
  /// Darwin renames `statfs` per architecture. From `sys/cdefs.h`:
  /// `__DARWIN_ONLY_64_BIT_INO_T` is 0 on `__x86_64__`, which makes
  /// `__DARWIN_SUF_64_BIT_INO_T` expand to `"$INODE64"`, so the 64-bit-inode
  /// entry point is exported as **`statfs$INODE64`**. On arm64 the macro is 1,
  /// the suffix is empty, and the symbol is plain **`statfs`**.
  ///
  /// The suffixed variant must be preferred: plain `statfs` on x86_64 is the
  /// *legacy* 32-bit-inode function whose struct has a different layout, so
  /// resolving it would produce wrong numbers rather than an error.
  final List<String> lookupSymbols;

  /// Bytes to allocate for the result. Deliberately larger than the real
  /// struct so a layout error cannot overrun the buffer.
  final int bufferBytes;

  /// Offset of the field that block counts are denominated in: `f_bsize` on
  /// Darwin's `struct statfs`, `f_frsize` on POSIX `struct statvfs`.
  final int unitOffset;

  /// Whether the field at [unitOffset] is 8 bytes wide rather than 4.
  final bool unitIs64;

  /// Offset of `f_blocks`, the total block count.
  final int blocksOffset;

  /// Offset of `f_bfree`, free blocks including those reserved for root.
  final int freeOffset;

  /// Offset of `f_bavail`, blocks available to an unprivileged process.
  final int availOffset;

  /// Whether the three count fields are 8 bytes wide rather than 4.
  final bool countsAre64;

  /// Creates a layout description.
  ///
  /// [lookupSymbols] defaults to `[symbol]` when the platform exports the
  /// symbol under its plain name on every architecture.
  const FsLayout({
    required this.symbol,
    List<String>? lookupSymbols,
    required this.bufferBytes,
    required this.unitOffset,
    required this.unitIs64,
    required this.blocksOffset,
    required this.freeOffset,
    required this.availOffset,
    required this.countsAre64,
  }) : lookupSymbols = lookupSymbols ?? const <String>[];

  /// The symbols to try, in order, falling back to [symbol] when no
  /// architecture-specific aliases are registered.
  ///
  /// A getter rather than a constructor default because a `const` initializer
  /// list cannot reference another field.
  List<String> get effectiveLookupSymbols => lookupSymbols.isEmpty ? <String>[symbol] : lookupSymbols;
}

/// Darwin `struct statfs` — macOS and iOS, arm64 and x86_64 alike.
///
/// `statfs` is used rather than `statvfs` for two independent reasons, both
/// verified against the real SDK headers:
///
/// * Darwin's `__darwin_fsblkcnt_t` is a 32-bit `unsigned int`, so
///   `struct statvfs` block counts silently wrap above 16 TiB.
/// * `struct statvfs`'s `f_bsize` is a 1 MiB I/O hint rather than a block
///   size, which yields a 256x overestimate. In `struct statfs` that hint
///   lives in `f_iosize`, safely out of the way.
const FsLayout darwinStatfsLayout = FsLayout(
  symbol: 'statfs',
  // x86_64 exports the 64-bit-inode variant as `statfs$INODE64`; arm64 exports
  // it as plain `statfs`. Preferring the suffixed name matters: plain `statfs`
  // on x86_64 is the legacy 32-bit-inode function with a different layout.
  lookupSymbols: <String>[r'statfs$INODE64', 'statfs'],
  bufferBytes: 2304,
  unitOffset: 0,
  unitIs64: false,
  blocksOffset: 8,
  freeOffset: 16,
  availOffset: 24,
  countsAre64: true,
);

/// POSIX `struct statvfs` on any LP64 platform.
///
/// Byte-identical across glibc, musl and bionic on both x86_64 and arm64.
const FsLayout posixStatvfsLp64Layout = FsLayout(
  symbol: 'statvfs',
  bufferBytes: 256,
  unitOffset: 8,
  unitIs64: true,
  blocksOffset: 16,
  freeOffset: 24,
  availOffset: 32,
  countsAre64: true,
);

/// POSIX `struct statvfs` on 32-bit bionic (`armeabi-v7a`, `x86`).
///
/// Android still ships these ABIs by default, so they are supported rather
/// than rejected. Counts are 32-bit, capping reporting at roughly 17 TB, which
/// no phone approaches.
const FsLayout posixStatvfsIlp32Layout = FsLayout(
  symbol: 'statvfs',
  bufferBytes: 128,
  unitOffset: 4,
  unitIs64: false,
  blocksOffset: 8,
  freeOffset: 12,
  availOffset: 16,
  countsAre64: false,
);

/// Selects the layout for the running platform, or `null` if unsupported.
///
/// [pointerSize] is `sizeOf<IntPtr>()`: 8 on 64-bit, 4 on 32-bit.
FsLayout? layoutFor({required bool isDarwin, required int pointerSize}) {
  if (isDarwin) {
    // Every Apple platform Dart runs on is 64-bit; 32-bit Darwin is not shipped.
    return pointerSize == 8 ? darwinStatfsLayout : null;
  }

  return switch (pointerSize) {
    8 => posixStatvfsLp64Layout,
    4 => posixStatvfsIlp32Layout,
    _ => null,
  };
}
