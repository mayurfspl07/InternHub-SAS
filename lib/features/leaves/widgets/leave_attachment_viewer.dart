import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../leave_repository.dart';

class LeaveAttachmentViewer {
  static Future<void> openAttachment(
    BuildContext context, {
    required int leaveId,
    String? filename,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2.5),
              SizedBox(height: 14),
              Text('Fetching attachment...', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await LeaveRepository().getAttachmentBytes(leaveId);
      if (context.mounted) Navigator.pop(context); // close loader

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
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Share / Save'),
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
        await Share.shareXFiles([XFile(file.path)], text: 'Leave Attachment: $safeName');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load attachment: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}
