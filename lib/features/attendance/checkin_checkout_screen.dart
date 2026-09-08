import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/custom_button.dart';

class CheckinCheckoutScreen extends ConsumerStatefulWidget {
  const CheckinCheckoutScreen({super.key});

  @override
  ConsumerState<CheckinCheckoutScreen> createState() => _CheckinCheckoutScreenState();
}

class _CheckinCheckoutScreenState extends ConsumerState<CheckinCheckoutScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scannerController;
  final ImagePicker _picker = ImagePicker();

  File? _capturedSelfie;
  Position? _currentPosition;
  bool _isLocating = true;
  bool _isProcessing = false;
  String? _errorMessage;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _determineLocation();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
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
          _errorMessage = 'Unable to get location coordinates. Tap Retry to attempt again.';
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
      );

      if (photo != null && mounted) {
        setState(() {
          _capturedSelfie = File(photo.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString()}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckIn() async {
    if (_capturedSelfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selfie photo is required to check in. Please capture your photo.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_currentPosition == null) {
      await _determineLocation();
      if (_currentPosition == null) return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await ref.read(appStateProvider.notifier).checkIn(
            photo: _capturedSelfie!,
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
          _errorMessage = 'Check-in failed. Please verify your internet connection.';
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleCheckOut() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await ref.read(appStateProvider.notifier).checkOut(
            photo: _capturedSelfie,
            latitude: _currentPosition?.latitude,
            longitude: _currentPosition?.longitude,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('👋 Checked Out! Working hours successfully recorded.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
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
          _errorMessage = 'Check-out failed. Please verify your connection.';
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(appStateProvider);
    final isCheckedIn = state.todayAttendance != null;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          isCheckedIn ? 'Check Out Verification' : 'Check In Verification',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scanner / Camera Viewfinder
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? AppColors.surfaceDark : const Color(0xFFF3F4F6),
                      border: Border.all(
                        color: _capturedSelfie != null ? AppColors.success : AppColors.primary,
                        width: 3,
                      ),
                      image: _capturedSelfie != null
                          ? DecorationImage(
                              image: FileImage(_capturedSelfie!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _capturedSelfie == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 54,
                                color: isDark ? Colors.white54 : Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Tap button below\nto capture selfie',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),

                  // Scanning laser animation line if photo not captured yet
                  if (_capturedSelfie == null)
                    AnimatedBuilder(
                      animation: _scannerController,
                      builder: (context, child) {
                        return Positioned(
                          top: 40 + (_scannerController.value * 180),
                          child: Container(
                            width: 220,
                            height: 2,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.8),
                                  blurRadius: 8,
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
            const SizedBox(height: 16),

            // Capture Photo Button
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: Text(_capturedSelfie == null ? 'Take Selfie Photo' : 'Retake Photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: _capturePhoto,
              ),
            ),
            const SizedBox(height: 24),

            // Error Banner if any
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    if (_permissionDenied) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Geolocator.openAppSettings(),
                        child: const Text('Open App Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _determineLocation,
                        child: const Text('Retry GPS Location', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // GPS Coordinates Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (_currentPosition != null ? AppColors.success : AppColors.warning).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: _currentPosition != null ? AppColors.success : AppColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentPosition != null ? 'GPS Geolocation Locked' : 'Fetching Coordinates...',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _currentPosition != null
                              ? 'Lat: ${_currentPosition!.latitude.toStringAsFixed(5)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(5)}'
                              : 'Waiting for high-accuracy GPS fix',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (_isLocating)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Submit Button
            CustomButton(
              text: isCheckedIn ? 'Confirm Check-Out' : 'Confirm Check-In',
              isLoading: _isProcessing,
              onPressed: _isProcessing
                  ? null
                  : (isCheckedIn ? _handleCheckOut : _handleCheckIn),
            ),
          ],
        ),
      ),
    );
  }
}
