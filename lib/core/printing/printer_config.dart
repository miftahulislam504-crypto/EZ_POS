import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// How this device reaches a receipt printer.
enum PrinterLink { none, network, bluetooth, usb }

String printerLinkLabel(PrinterLink l) => switch (l) {
      PrinterLink.none => 'System print dialog',
      PrinterLink.network => 'Network (Wi-Fi or Ethernet)',
      PrinterLink.bluetooth => 'Bluetooth',
      PrinterLink.usb => 'USB',
    };

/// A printer found while scanning.
class FoundPrinter {
  const FoundPrinter({required this.name, this.address, this.vendorId, this.productId});

  final String name;

  /// Bluetooth address.
  final String? address;
  final String? vendorId;
  final String? productId;

  String get key => '${address ?? ''}|${vendorId ?? ''}|${productId ?? ''}|$name';
}

/// The receipt printer set up on this device. Printers belong to a device (a counter tablet, a phone), not to the
/// business, so this is kept on the device and never sent to the server.
class PrinterConfig {
  const PrinterConfig({
    this.link = PrinterLink.none,
    this.name = '',
    this.address = '',
    this.port = 9100,
    this.vendorId,
    this.productId,
    this.isBle = false,
    this.cutPaper = true,
    this.openDrawer = false,
  });

  final PrinterLink link;
  final String name;

  /// IP address for network printers, Bluetooth address for Bluetooth printers.
  final String address;
  final int port;
  final String? vendorId;
  final String? productId;
  final bool isBle;
  final bool cutPaper;
  final bool openDrawer;

  bool get isConfigured => switch (link) {
        PrinterLink.none => false,
        PrinterLink.network => address.trim().isNotEmpty,
        PrinterLink.bluetooth => address.trim().isNotEmpty,
        PrinterLink.usb => (vendorId ?? '').isNotEmpty && (productId ?? '').isNotEmpty,
      };

  String get summary => !isConfigured
      ? 'Not set up. Receipts open the system print dialog.'
      : switch (link) {
          PrinterLink.network => '${name.isEmpty ? 'Network printer' : name}  |  $address:$port',
          PrinterLink.bluetooth => '${name.isEmpty ? 'Bluetooth printer' : name}  |  $address',
          PrinterLink.usb => name.isEmpty ? 'USB printer' : name,
          PrinterLink.none => '',
        };

  PrinterConfig copyWith({
    PrinterLink? link,
    String? name,
    String? address,
    int? port,
    String? vendorId,
    String? productId,
    bool? isBle,
    bool? cutPaper,
    bool? openDrawer,
  }) =>
      PrinterConfig(
        link: link ?? this.link,
        name: name ?? this.name,
        address: address ?? this.address,
        port: port ?? this.port,
        vendorId: vendorId ?? this.vendorId,
        productId: productId ?? this.productId,
        isBle: isBle ?? this.isBle,
        cutPaper: cutPaper ?? this.cutPaper,
        openDrawer: openDrawer ?? this.openDrawer,
      );

  Map<String, dynamic> toJson() => {
        'link': link.name,
        'name': name,
        'address': address,
        'port': port,
        'vendorId': vendorId,
        'productId': productId,
        'isBle': isBle,
        'cutPaper': cutPaper,
        'openDrawer': openDrawer,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic> j) => PrinterConfig(
        link: PrinterLink.values.firstWhere((l) => l.name == j['link'], orElse: () => PrinterLink.none),
        name: (j['name'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 9100,
        vendorId: j['vendorId'] as String?,
        productId: j['productId'] as String?,
        isBle: j['isBle'] == true,
        cutPaper: j['cutPaper'] != false,
        openDrawer: j['openDrawer'] == true,
      );

  static const _key = 'ez_pos.receipt_printer';

  static Future<PrinterConfig> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || raw.isEmpty) return const PrinterConfig();
      return PrinterConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PrinterConfig();
    }
  }

  Future<void> save() async => (await SharedPreferences.getInstance()).setString(_key, jsonEncode(toJson()));
}
