import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/constants/app_colors.dart';
import '../attendance_repository.dart';

class AuthedAttendanceImage extends StatefulWidget {
  final int? attendanceId;
  final String? photoType; // 'checkin' | 'checkout'
  final String? photoUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final String fallbackLabel;

  const AuthedAttendanceImage({
    super.key,
    this.attendanceId,
    this.photoType,
    this.photoUrl,
    this.width,
    this.height,
    this.borderRadius,
    this.fallbackLabel = 'No photo available',
  });

  @override
  State<AuthedAttendanceImage> createState() => _AuthedAttendanceImageState();
}

class _AuthedAttendanceImageState extends State<AuthedAttendanceImage> {
  Uint8List? _imageBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant AuthedAttendanceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attendanceId != widget.attendanceId ||
        oldWidget.photoType != widget.photoType ||
        oldWidget.photoUrl != widget.photoUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.photoUrl == null && (widget.attendanceId == null || widget.photoType == null)) {
      if (mounted) setState(() => _imageBytes = null);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Uint8List? bytes;
      if (widget.attendanceId != null && widget.photoType != null) {
        bytes = await AttendanceRepository().fetchAttendancePhotoBytes(
          attendanceId: widget.attendanceId!,
          type: widget.photoType!,
        );
      }

      if (bytes == null && widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
        final urlStr = widget.photoUrl!.startsWith('http')
            ? widget.photoUrl!
            : ApiConfig.url(widget.photoUrl!);
        final client = ApiClient();
        bytes = await client.getBytes(urlStr);
      }

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showFullImage(BuildContext context) {
    if (_imageBytes == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(_imageBytes!, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = widget.borderRadius ?? BorderRadius.circular(16);

    if (_isLoading) {
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
          borderRadius: r,
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_imageBytes != null && _imageBytes!.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showFullImage(context),
        child: ClipRRect(
          borderRadius: r,
          child: Container(
            width: widget.width ?? double.infinity,
            height: widget.height ?? double.infinity,
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Image.memory(
              _imageBytes!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => _buildFallback(isDark, r),
            ),
          ),
        ),
      );
    }

    return _buildFallback(isDark, r);
  }

  Widget _buildFallback(bool isDark, BorderRadius r) {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark.withValues(alpha: 0.5) : const Color(0xFFF9FAFB),
        borderRadius: r,
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt_outlined,
            size: 28,
            color: isDark ? Colors.white38 : AppColors.textTertiaryLight,
          ),
          const SizedBox(height: 8),
          Text(
            widget.fallbackLabel,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
