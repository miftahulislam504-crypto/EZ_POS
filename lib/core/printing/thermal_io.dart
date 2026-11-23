import 'dart:async';
import 'dart:io';

import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:permission_handler/permission_handler.dart';

import 'printer_config.dart';

/// Real printer transports for Android, iOS and desktop.
///   Network: a plain TCP socket to port 9100 (works anywhere dart:io works).
///   Bluetooth and USB: through the flutter_pos_printer_platform_image_3 plugin (Android: classic Bluetooth and USB,
///   iOS: Bluetooth Low Energy printers).
bool get thermalSupported => true;

Set<PrinterLink> get availableLinks => {
      PrinterLink.network,
      if (Platform.isAndroid || Platform.isIOS) PrinterLink.bluetooth,
      if (Platform.isAndroid) PrinterLink.usb,
    };

String get thermalUnavailableReason => '';

Future<void> sendToPrinter(PrinterConfig config, List<int> bytes) {
  switch (config.link) {
    case PrinterLink.network:
      return _sendNetwork(config, bytes);
    case PrinterLink.bluetooth:
      return _sendBluetooth(config, bytes);
    case PrinterLink.usb:
      return _sendUsb(config, bytes);
    case PrinterLink.none:
      return Future.error(StateError('No printer is set up on this device.'));
  }
}

Future<void> _sendNetwork(PrinterConfig c, List<int> bytes) async {
  Socket socket;
  try {
    socket = await Socket.connect(c.address.trim(), c.port, timeout: const Duration(seconds: 5));
  } on SocketException {
    throw Exception('Cannot reach the printer at ${c.address}:${c.port}. Check that it is on and on the same network.');
  } on TimeoutException {
    throw Exception('The printer at ${c.address}:${c.port} did not answer. Check the address and the network.');
  }
  try {
    for (var i = 0; i < bytes.length; i += 4096) {
      socket.add(bytes.sublist(i, i + 4096 > bytes.length ? bytes.length : i + 4096));
    }
    await socket.flush();
  } finally {
    await socket.close();
    socket.destroy();
  }
}

Future<void> _askBluetoothPermission() async {
  if (!Platform.isAndroid) return;
  // Android 12 and newer need these at run time. Older versions ignore them.
  await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.locationWhenInUse].request();
}

/// Sends in small pieces with a short pause so printers with a small buffer do not drop data.
Future<void> _sendChunks(List<int> bytes, Future<void> Function(List<int>) send, {int size = 1024}) async {
  for (var i = 0; i < bytes.length; i += size) {
    await send(bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size));
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<void> _sendBluetooth(PrinterConfig c, List<int> bytes) async {
  await _askBluetoothPermission();
  final manager = PrinterManager.instance;
  final connected = Completer<void>();
  StreamSubscription<BTStatus>? sub;
  sub = manager.stateBluetooth.listen((s) {
    if (s == BTStatus.connected && !connected.isCompleted) connected.complete();
  });
  try {
    await manager.connect(
      type: PrinterType.bluetooth,
      model: BluetoothPrinterInput(name: c.name, address: c.address, isBle: c.isBle, autoConnect: false),
    );
    if (Platform.isAndroid) {
      await connected.future.timeout(const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await _sendChunks(bytes, (chunk) => manager.send(type: PrinterType.bluetooth, bytes: chunk));
  } on TimeoutException {
    throw Exception('Could not connect to ${c.name.isEmpty ? 'the printer' : c.name}. Switch it on, keep it close, and pair it in the phone Bluetooth settings first.');
  } finally {
    await sub.cancel();
    try {
      await manager.disconnect(type: PrinterType.bluetooth);
    } catch (_) {}
  }
}

Future<void> _sendUsb(PrinterConfig c, List<int> bytes) async {
  final manager = PrinterManager.instance;
  try {
    await manager.connect(
      type: PrinterType.usb,
      model: UsbPrinterInput(name: c.name, productId: c.productId, vendorId: c.vendorId),
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _sendChunks(bytes, (chunk) => manager.send(type: PrinterType.usb, bytes: chunk), size: 4096);
  } finally {
    try {
      await manager.disconnect(type: PrinterType.usb);
    } catch (_) {}
  }
}

Future<List<FoundPrinter>> discoverPrinters(PrinterLink link, {Duration timeout = const Duration(seconds: 6)}) async {
  if (link != PrinterLink.bluetooth && link != PrinterLink.usb) return const [];
  if (link == PrinterLink.bluetooth) await _askBluetoothPermission();
  final found = <String, FoundPrinter>{};
  final sub = PrinterManager.instance
      .discovery(type: link == PrinterLink.bluetooth ? PrinterType.bluetooth : PrinterType.usb, isBle: link == PrinterLink.bluetooth && Platform.isIOS)
      .listen((d) {
    final p = FoundPrinter(name: d.name, address: d.address, vendorId: d.vendorId, productId: d.productId);
    found[p.key] = p;
  });
  await Future<void>.delayed(timeout);
  await sub.cancel();
  return found.values.toList();
}
