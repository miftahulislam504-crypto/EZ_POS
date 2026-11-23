import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/json.dart';
import 'providers.dart';

/// Files kept for customers (NID copies, photos), installment plans (agreements), suppliers, purchases and expenses.
/// The files sit in the private "documents" bucket; the database keeps one record per file.
class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.docType,
    required this.storagePath,
    required this.createdAt,
    this.fileName,
    this.note,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String docType;
  final String storagePath;
  final String? fileName;
  final String? note;
  final DateTime? createdAt;

  String get extension {
    final name = (fileName ?? storagePath).toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  bool get isImage => const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'}.contains(extension);
  bool get isPdf => extension == 'pdf';

  factory DocumentRecord.fromJson(Map<String, dynamic> j) => DocumentRecord(
        id: j['id'] as String,
        entityType: j['entity_type'] as String,
        entityId: j['entity_id'] as String,
        docType: (j['doc_type'] as String?) ?? 'other',
        storagePath: j['storage_path'] as String,
        fileName: j['file_name'] as String?,
        note: j['note'] as String?,
        createdAt: parseDate(j['created_at']),
      );
}

/// Document kinds offered for each record type: (stored value, label).
const Map<String, List<(String, String)>> kDocumentKinds = {
  'customer': [
    ('nid_front', 'NID front'),
    ('nid_back', 'NID back'),
    ('photo', 'Photo'),
    ('other', 'Other document'),
  ],
  'installment': [
    ('agreement', 'Signed agreement'),
    ('guarantor_nid', 'Guarantor NID'),
    ('other', 'Other document'),
  ],
  'supplier': [
    ('bill', 'Supplier bill'),
    ('other', 'Other document'),
  ],
  'purchase': [
    ('bill', 'Supplier bill or challan'),
    ('other', 'Other document'),
  ],
  'expense': [
    ('receipt', 'Receipt'),
    ('other', 'Other document'),
  ],
};

String documentKindLabel(String entityType, String kind) {
  for (final k in kDocumentKinds[entityType] ?? const <(String, String)>[]) {
    if (k.$1 == kind) return k.$2;
  }
  return 'Document';
}

const int kMaxDocumentBytes = 10 * 1024 * 1024;

String _contentType(String extension) => switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };

/// Keeps the storage path simple: letters, digits, dot, dash and underscore only.
String safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return cleaned.isEmpty ? 'file' : (cleaned.length > 80 ? cleaned.substring(cleaned.length - 80) : cleaned);
}

class DocumentsRepository {
  DocumentsRepository(this._client, this._businessId);

  final SupabaseClient _client;
  final String _businessId;

  static const _bucket = 'documents';

  Future<List<DocumentRecord>> list(String entityType, String entityId) async {
    final rows = await _client
        .from('documents')
        .select()
        .eq('entity_type', entityType)
        .eq('entity_id', entityId)
        .order('created_at', ascending: false);
    return [for (final r in rows) DocumentRecord.fromJson(asMap(r))];
  }

  /// Uploads the file, then records it. If the record cannot be saved the uploaded file is removed again.
  Future<void> upload({
    required String entityType,
    required String entityId,
    required String docType,
    required String fileName,
    required Uint8List bytes,
    String? note,
  }) async {
    if (bytes.isEmpty) throw Exception('The file is empty.');
    if (bytes.length > kMaxDocumentBytes) throw Exception('The file is larger than 10 MB. Choose a smaller file or photo.');
    final safe = safeFileName(fileName);
    final dot = safe.lastIndexOf('.');
    final ext = dot < 0 ? '' : safe.substring(dot + 1).toLowerCase();
    final path = '$_businessId/$entityType/$entityId/${const Uuid().v4()}-$safe';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentType(ext), upsert: false),
        );
    try {
      await _client.rpc('add_document', params: {
        'p': {
          'entity_type': entityType,
          'entity_id': entityId,
          'doc_type': docType,
          'storage_path': path,
          'file_name': fileName,
          'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
        },
      });
    } catch (_) {
      try {
        await _client.storage.from(_bucket).remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  /// A link that works for two minutes. The bucket is private, so files are never opened by a permanent address.
  Future<String> signedUrl(DocumentRecord d) => _client.storage.from(_bucket).createSignedUrl(d.storagePath, 120);

  /// Deletes the record first (permission checked in the database), then the file.
  Future<void> delete(DocumentRecord d) async {
    final path = await _client.rpc('delete_document', params: {'p_id': d.id});
    try {
      await _client.storage.from(_bucket).remove([(path as String?) ?? d.storagePath]);
    } catch (_) {
      // The record is gone, so the file can no longer be reached from the app. Cleaning up later is harmless.
    }
  }
}

final documentsRepoProvider = Provider<DocumentsRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  return DocumentsRepository(ref.watch(supabaseProvider), user.businessId);
});

typedef DocumentsQuery = ({String type, String id});

final documentsProvider = FutureProvider.autoDispose.family<List<DocumentRecord>, DocumentsQuery>((ref, q) {
  return ref.watch(documentsRepoProvider).list(q.type, q.id);
});
