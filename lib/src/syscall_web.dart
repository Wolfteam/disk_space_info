import 'disk_space_info_base.dart';

/// Web has no filesystem to measure, so every query is unknown.
///
/// This file exists so the package still compiles under dart2js and dart2wasm,
/// where both `dart:ffi` and `dart:io` are unavailable. It is selected by the
/// conditional import in `disk_space_info_base.dart`, and deliberately imports
/// neither — which is why path resolution lives behind this seam rather than
/// in front of it.
DiskSpaceInfo? queryNative(String path) => null;
