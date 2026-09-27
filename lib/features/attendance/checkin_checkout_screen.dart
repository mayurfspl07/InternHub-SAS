import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';

class CheckinCheckoutScreen extends ConsumerStatefulWidget {
  final bool? isCheckOut;
  const CheckinCheckoutScreen({super.key, this.isCheckOut});

  @override
  ConsumerState<CheckinCheckoutScreen> createState() => _CheckinCheckoutScreenState();
}

class _CheckinCheckoutScreenState extends ConsumerState<CheckinCheckoutScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _scannerController;

  CameraController? _cameraController;
  List<CameraDescription>? _availableCameras;
  bool _isCameraInitialized = false;
  bool _isCameraInitializing = true;

  File? _capturedSelfie;
  Position? _currentPosition;
  bool _isLocating = true;
  bool _isProcessing = false;
  String? _errorMessage;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _determineLocation();
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;
    setState(() {
      _isCameraInitializing = true;
    });

    try {
      _availableCameras = await availableCameras();
      if (_availableCameras == null || _availableCameras!.isEmpty) {
        if (mounted) {
          setState(() {
            _isCameraInitializing = false;
            _isCameraInitialized = false;
          });
        }
        return;
      }

      // Find front camera or fallback to first available
      final frontCamera = _availableCameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _availableCameras!.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _cameraController = controller;
      await controller.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isCameraInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Live camera init error: $e');
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _isCameraInitializing = false;
        });
      }
    }
  }

  Future<void> _determineLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
      _permissionDenied = false;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are disabled. Please enable GPS.';
          _isLocating = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _permissionDenied = true;
            _errorMessage = 'Location permission is required for attendance verification.';
            _isLocating = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _permissionDenied = true;
          _errorMessage = 'Location permissions are permanently denied. Please open Settings to allow access.';
          _isLocating = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to get location coordinates. Tap to retry.';
          _isLocating = false;
        });
      }
    }
  }

  Future<File?> _captureCurrentFrame() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile picture = await _cameraController!.takePicture();
        final file = File(picture.path);
        if (mounted) {
          setState(() => _capturedSelfie = file);
        }
        return file;
      } catch (e) {
        debugPrint('Live camera frame capture failed: $e');
      }
    }
    return null;
  }

  Future<void> _handleConfirmAction(bool isCheckOutMode) async {
    if (_isProcessing) return;

    // Ensure GPS coordinates are locked
    if (_currentPosition == null) {
      await _determineLocation();
      if (_currentPosition == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acquiring GPS location. Please wait a moment...'),
            backgroundColor: AppColors.ink,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Capture live photo right now from the in-circle camera stream
      final photo = await _captureCurrentFrame();

      // Both check-in and check-out need a selfie and the current location.
      if (photo == null) {
        setState(() {
          _isProcessing = false;
          _errorMessage = _isCameraInitialized
              ? 'Could not take the photo. Hold still and tap Confirm again.'
              : 'The camera is not ready. Allow camera access for InternHub and try again.';
        });
        return;
      }

      if (isCheckOutMode) {
        await ref.read(appStateProvider.notifier).checkOut(
              photo: photo,
              latitude: _currentPosition!.latitude,
              longitude: _currentPosition!.longitude,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('👋 Checked Out! Working hours recorded.'),
              backgroundColor: AppColors.ink,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        await ref.read(appStateProvider.notifier).checkIn(
              photo: photo,
              latitude: _currentPosition!.latitude,
              longitude: _currentPosition!.longitude,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Verified & Checked In Successfully!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verification failed. Please check your connection and try again.';
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isCheckOutMode = widget.isCheckOut ??
        (state.todayAttendance != null && state.todayAttendance?.checkOut == null);

    final now = DateTime.now();
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final formattedTime = DateFormat('hh:mm a').format(now);

    final bool isReadyToSubmit = !_isProcessing && _currentPosition != null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: isCheckOutMode ? 'Check Out Verification' : 'Check In Verification',
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 24,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Subtitle / Status badge
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isCheckOutMode
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isCheckOutMode
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : AppColors.success.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCheckOutMode ? AppColors.primary : AppColors.success,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isCheckOutMode ? 'SHIFT CHECK-OUT' : 'SHIFT CHECK-IN',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: isCheckOutMode ? AppColors.primaryInk : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Align your face in the circle & tap confirm',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Biometric In-Circle Live Camera Viewfinder
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer Glowing Aura Ring
                            Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (isCheckOutMode ? AppColors.primary : AppColors.success)
                                    .withValues(alpha: 0.08),
                                border: Border.all(
                                  color: (isCheckOutMode ? AppColors.primary : AppColors.success)
                                      .withValues(alpha: 0.3),
                                  width: 4,
                                ),
                              ),
                            ),

                            // Inner Circle (Live Camera Feed or Frozen Capture on Submit)
                            Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.surfaceMuted,
                                border: Border.all(
                                  color: isCheckOutMode ? AppColors.primary : AppColors.success,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipOval(
                                child: _buildLiveCameraView(),
                              ),
                            ),

                            // Laser Scanning Line (sweeps continuously over the live camera)
                            if (_capturedSelfie == null && !_isCameraInitializing)
                              AnimatedBuilder(
                                animation: _scannerController,
                                builder: (context, child) {
                                  return Positioned(
                                    top: 36 + (_scannerController.value * 148),
                                    child: Container(
                                      width: 175,
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.95),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Error Banner if any
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_permissionDenied) ...[
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: () => Geolocator.openAppSettings(),
                                        child: const Text(
                                          'Open App Settings →',
                                          style: TextStyle(
                                            color: AppColors.danger,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: _determineLocation,
                                        child: const Text(
                                          'Tap to Retry GPS',
                                          style: TextStyle(
                                            color: AppColors.danger,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Verification Details Card (GPS + Date/Time)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: AppShadows.soft,
                        ),
                        child: Column(
                          children: [
                            // GPS Item
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: (_currentPosition != null ? AppColors.success : AppColors.warning)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: _currentPosition != null ? AppColors.success : AppColors.warning,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            _currentPosition != null
                                                ? 'GPS Geolocation Locked'
                                                : 'Detecting Location...',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          if (_currentPosition != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.success.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'HIGH ACCURACY',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _currentPosition != null
                                            ? 'Lat: ${_currentPosition!.latitude.toStringAsFixed(5)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(5)}'
                                            : 'Waiting for high-accuracy GPS signal',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isLocating)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else if (_currentPosition != null)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.success,
                                    size: 20,
                                  ),
                              ],
                            ),

                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Divider(
                                height: 1,
                                color: AppColors.border,
                              ),
                            ),

                            // Timestamp Item
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.access_time_filled_rounded,
                                    color: AppColors.primaryInk,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Verification Timestamp',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$formattedDate • $formattedTime',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isCheckOutMode ? AppColors.primary : AppColors.success)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    formattedTime,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isCheckOutMode ? AppColors.primaryInk : AppColors.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),
                      const SizedBox(height: 20),

                      // Single-Click Confirm & Capture Button
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCheckOutMode ? AppColors.cocoa : AppColors.primary,
                            foregroundColor: isCheckOutMode ? Colors.white : AppColors.onPrimary,
                            disabledBackgroundColor: AppColors.border,
                            disabledForegroundColor: AppColors.textTertiary,
                            elevation: isReadyToSubmit ? 4 : 0,
                            shadowColor: (isCheckOutMode ? AppColors.cocoa : AppColors.primary)
                                .withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isReadyToSubmit
                              ? () => _handleConfirmAction(isCheckOutMode)
                              : null,
                          child: _isProcessing
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: isCheckOutMode ? Colors.white : AppColors.onPrimary,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Capturing & Verifying...',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isCheckOutMode ? Colors.white : AppColors.onPrimary,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isCheckOutMode
                                          ? Icons.logout_rounded
                                          : Icons.fingerprint_rounded,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isCheckOutMode ? 'Confirm Check-Out' : 'Confirm Check-In',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Encrypted Biometric Audit Notice
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'One-click biometric snapshot & tamper-proof GPS log',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveCameraView() {
    // 1. If photo was captured on submit, show it
    if (_capturedSelfie != null) {
      return Image.file(
        _capturedSelfie!,
        fit: BoxFit.cover,
        width: 220,
        height: 220,
      );
    }

    // 2. Live camera feed directly inside the circle
    if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
      return SizedBox(
        width: 220,
        height: 220,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 220,
            height: _cameraController!.value.previewSize?.width ?? 220,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    }

    // 3. Camera starting up
    if (_isCameraInitializing) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Starting live camera...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      );
    }

    // 4. If camera requires native rebuild (e.g. app wasn't restarted after adding camera plugin)
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.videocam_off_rounded,
          size: 42,
          color: AppColors.primaryInk.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Camera Drivers Unlinked',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Please restart "flutter run" in terminal to link camera',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
