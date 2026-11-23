// Picks the real transport on devices (dart:io available) and a stub on the web.
export 'thermal_stub.dart' if (dart.library.io) 'thermal_io.dart';
