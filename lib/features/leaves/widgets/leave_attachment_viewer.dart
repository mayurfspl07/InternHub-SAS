import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../leave_repository.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class LeaveAttachmentViewer {
  static Future<void> openAttachment(
    BuildContext context, {
    required int leaveId,
    String? filename,
  }) async {

    // Loading dialog; tracked so an error later can't pop the page underneath instead.
    var loaderOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 14),
              Text('Opening attachment…', style: AppTypography.body.copyWith(color: AppColors.ink)),
            ],
          ),
        ),
      ),
    );
    void closeLoader() {
      if (loaderOpen && context.mounted) Navigator.pop(context);
      loaderOpen = false;
    }

    try {
      final bytes = await LeaveRepository().getAttachmentBytes(leaveId);
      closeLoader();

      if (bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attachment is empty or unavailable')),
          );
        }
        return;
      }

      // Check if image
      final name = filename?.toLowerCase() ?? '';
      final isImage = name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.webp') ||
          bytes.length > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8; // JPEG header

      if (isImage && context.mounted) {
        // Show in-app image preview modal
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    tooltip: 'Close',
                    style: IconButton.styleFrom(backgroundColor: AppColors.ink.withValues(alpha: 0.7)),
                    icon: const Icon(Icons.close_rounded, color: AppColors.surface, size: 24),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Share or save'),
                    onPressed: () async {
                      final tempDir = await getTemporaryDirectory();
                      final safeName = filename ?? 'leave_attachment_$leaveId.jpg';
                      final file = File('${tempDir.path}/$safeName');
                      await file.writeAsBytes(bytes);
                      await Share.shareXFiles([XFile(file.path)]);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Non-image file (PDF, DOC, etc.): Save to temp and invoke native share/viewer
        final tempDir = await getTemporaryDirectory();
        final safeName = filename ?? 'leave_attachment_$leaveId.bin';
        final file = File('${tempDir.path}/$safeName');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Leave attachment: $safeName');
      }
    } catch (e) {
      closeLoader();
      if (context.mounted) showApiError(context, e, prefix: "Couldn't open the attachment");
    }
  }
}
