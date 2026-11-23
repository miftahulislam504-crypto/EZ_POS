import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/documents_data.dart';
import '../errors.dart';
import '../security/password_confirm.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import 'buttons.dart';
import 'feedback.dart';
import 'inputs.dart';
import 'layout.dart';
import 'surfaces.dart';

/// Files that belong to one record: NID copies and photos on a customer, signed agreements on an installment plan,
/// bills on a supplier or purchase, receipts on an expense. Files live in a private bucket and open through
/// short-lived links. The parent screen decides who sees the section; the database checks every upload and delete.
class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({
    super.key,
    required this.entityType,
    required this.entityId,
    this.title = 'Attachments',
    this.subtitle,
    this.canEdit = true,
    this.canDelete = true,
  });

  final String entityType;
  final String entityId;
  final String title;
  final String? subtitle;
  final bool canEdit;
  final bool canDelete;

  DocumentsQuery get _query => (type: entityType, id: entityId);

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await showAppSheet<bool>(
      context,
      title: 'Add attachment',
      builder: (ctx) => _AddAttachmentSheet(entityType: entityType, entityId: entityId),
    );
    if (added == true) {
      ref.invalidate(documentsProvider(_query));
      if (context.mounted) showToast(context, 'Attachment saved');
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, DocumentRecord d) async {
    try {
      final url = await ref.read(documentsRepoProvider).signedUrl(d);
      if (!context.mounted) return;
      if (d.isImage) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null ? child : const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
                    errorBuilder: (c, e, s) => const SizedBox(height: 160, child: Center(child: Text('This image cannot be shown. Try opening it again.'))),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ),
              ],
            ),
          ),
        );
        return;
      }
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showToast(context, 'The file could not be opened on this device.', error: true);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, DocumentRecord d) async {
    final sure = await confirmDialog(
      context,
      title: 'Delete this file?',
      message: '${d.fileName ?? documentKindLabel(entityType, d.docType)} will be removed permanently.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!sure || !context.mounted) return;
    if (!await confirmSensitive(context, ref)) return;
    try {
      await ref.read(documentsRepoProvider).delete(d);
      ref.invalidate(documentsProvider(_query));
      if (context.mounted) showToast(context, 'File deleted');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(documentsProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          subtitle: subtitle,
          trailing: canEdit ? AppButton('Add', icon: Icons.attach_file_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _add(context, ref)) : null,
        ),
        value.when(
          loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Skeleton(height: 60, radius: 16)),
          error: (e, _) => AppCard(child: Text(friendlyError(e), style: TextStyle(color: c.danger))),
          data: (docs) {
            if (docs.isEmpty) {
              return AppCard(
                child: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: c.textMuted),
                    const SizedBox(width: 12),
                    Expanded(child: Text(canEdit ? 'No files yet. Use Add to attach a photo or PDF.' : 'No files attached.', style: TextStyle(color: c.textMuted))),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final d in docs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => _open(context, ref, d),
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      child: Row(
                        children: [
                          IconBadge(d.isImage ? Icons.image_outlined : (d.isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined),
                              tone: d.isImage ? Tone.info : Tone.brand, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(documentKindLabel(entityType, d.docType), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  [if (d.fileName != null) d.fileName!, Fmt.date(d.createdAt)].join('  |  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(color: c.textMuted),
                                ),
                                if (d.note != null) Text(d.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            onSelected: (v) {
                              if (v == 'open') _open(context, ref, d);
                              if (v == 'delete') _delete(context, ref, d);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'open', child: Text('Open')),
                              if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AddAttachmentSheet extends ConsumerStatefulWidget {
  const _AddAttachmentSheet({required this.entityType, required this.entityId});

  final String entityType;
  final String entityId;

  @override
  ConsumerState<_AddAttachmentSheet> createState() => _AddAttachmentSheetState();
}

class _AddAttachmentSheetState extends ConsumerState<_AddAttachmentSheet> {
  late String _kind = (kDocumentKinds[widget.entityType] ?? const [('other', 'Other document')]).first.$1;
  final _note = TextEditingController();
  Uint8List? _bytes;
  String? _name;
  bool _busy = false;
  String? _error;

  bool get _hasCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 85);
      if (f == null) return;
      final b = await f.readAsBytes();
      setState(() {
        _bytes = b;
        _name = f.name.isEmpty ? 'photo.jpg' : f.name;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _pickFile() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      final f = (r == null || r.files.isEmpty) ? null : r.files.first;
      if (f == null || f.bytes == null) return;
      setState(() {
        _bytes = f.bytes;
        _name = f.name;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _upload() async {
    if (_bytes == null || _name == null) {
      setState(() => _error = 'Choose a photo or file first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(documentsRepoProvider).upload(
            entityType: widget.entityType,
            entityId: widget.entityId,
            docType: _kind,
            fileName: _name!,
            bytes: _bytes!,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kinds = kDocumentKinds[widget.entityType] ?? const [('other', 'Other document')];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerField<String>(
          label: 'Type',
          value: _kind,
          options: [for (final k in kinds) PickerOption(k.$1, k.$2)],
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (_hasCamera) AppButton('Take photo', icon: Icons.photo_camera_outlined, kind: ButtonKind.secondary, dense: true, onPressed: _busy ? null : () => _pickImage(ImageSource.camera)),
            AppButton('Choose photo', icon: Icons.photo_library_outlined, kind: ButtonKind.secondary, dense: true, onPressed: _busy ? null : () => _pickImage(ImageSource.gallery)),
            AppButton('Choose PDF or file', icon: Icons.upload_file_rounded, kind: ButtonKind.secondary, dense: true, onPressed: _busy ? null : _pickFile),
          ],
        ),
        if (_name != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.success, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('$_name  (${(_bytes!.length / 1024).toStringAsFixed(0)} KB)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        const SizedBox(height: 14),
        AppTextField(controller: _note, label: 'Note (optional)', maxLines: 2),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 18),
        AppButton('Upload', icon: Icons.cloud_upload_outlined, expand: true, loading: _busy, onPressed: _upload),
        const SizedBox(height: 6),
        Text('Files up to 10 MB. Only people with access to this record can open them.', style: context.text.bodySmall?.copyWith(color: c.textMuted), textAlign: TextAlign.center),
      ],
    );
  }
}
