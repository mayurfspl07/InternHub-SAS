import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import 'intern_attendance_screen.dart';
import 'staff_attendance_screen.dart';

class AttendanceHomeScreen extends ConsumerWidget {
  final String? initialTab; // 'all' | 'today' for staff

  const AttendanceHomeScreen({super.key, this.initialTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appStateProvider).currentUser;

    if (user.role == UserRole.intern) {
      return const InternAttendanceScreen();
    } else {
      return StaffAttendanceScreen(initialTab: initialTab ?? 'all');
    }
  }
}
