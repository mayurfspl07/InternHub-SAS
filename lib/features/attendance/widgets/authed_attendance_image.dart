import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/constants/app_colors.dart';
import '../attendance_repository.dart';
import '../../../core/constants/app_typography.dart';

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
  bool _failed = false;

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
          _failed = true;
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
              tooltip: 'Close',
              icon: const CircleAvatar(
                backgroundColor: AppColors.ink,
                child: Icon(Icons.close, color: AppColors.surface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius ?? BorderRadius.circular(16);

    if (_isLoading) {
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: r,
          border: Border.all(
            color: AppColors.border,
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
                color: AppColors.border,
              ),
            ),
            child: Image.memory(
              _imageBytes!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => _buildFallback(r),
            ),
          ),
        ),
      );
    }

    return _buildFallback(r);
  }

  Widget _buildFallback(BorderRadius r) {
    // A failed download can be retried; a missing photo just says so.
    if (_failed) {
      return InkWell(
        borderRadius: r,
        onTap: () {
          setState(() => _failed = false);
          _loadImage();
        },
        child: _placeholder(r, Icons.refresh_rounded, "Couldn't load photo. Tap to retry."),
      );
    }
    return _placeholder(r, Icons.camera_alt_outlined, widget.fallbackLabel);
  }

  Widget _placeholder(BorderRadius r, IconData icon, String label) {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: r,
        border: Border.all(
          color: AppColors.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
