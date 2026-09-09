import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/leave_model.dart';
import '../../shared/models/user_model.dart';
import 'leave_repository.dart';
import 'widgets/apply_leave_dialog.dart';
import 'widgets/leave_balance_cards.dart';
import 'widgets/manage_leave_queue_widget.dart';
import 'widgets/my_leave_history_widget.dart';

class LeaveDashboardScreen extends ConsumerStatefulWidget {
  const LeaveDashboardScreen({super.key});

  @override
  ConsumerState<LeaveDashboardScreen> createState() => _LeaveDashboardScreenState();
}

class _LeaveDashboardScreenState extends ConsumerState<LeaveDashboardScreen> {
  bool _isLoading = false;
  LeaveMineResponse? _mineResponse;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = ref.read(appStateProvider).currentUser;
    // Only intern needs to fetch mine
    if (user.role == UserRole.intern) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final res = await LeaveRepository().getMine();
        if (mounted) {
          setState(() {
            _mineResponse = res;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString().replaceAll('Exception:', '').trim();
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    final canRequestLeave = user.role == UserRole.intern;
    final canApproveLeave =
        user.role == UserRole.admin || user.role == UserRole.mentor || user.role == UserRole.superadmin;

    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top PageHeader row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (canPop) ...[
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leave',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            canRequestLeave
                                ? 'Submit leave requests and view your quota.'
                                : 'Review and approve pending intern leave requests.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canRequestLeave) ...[
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cardYellow,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18, color: Colors.black),
                        label: Text(
                          'Apply for Leave',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.black,
                          ),
                        ),
                        onPressed: () {
                          final balance = _mineResponse?.balance ??
                              const LeaveBalance(used: 0, quota: 15, remaining: 15);
                          ApplyLeaveDialog.show(
                            context,
                            balance: balance,
                            onSuccess: _loadData,
                          );
                        },
                      ),
                    ] else ...[
                      IconButton(
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                        ),
                        tooltip: 'Refresh',
                        onPressed: _loadData,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),

                // ==================== INTERN VIEW ====================
                if (canRequestLeave) ...[
                  if (_isLoading && _mineResponse == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                    )
                  else if (_errorMessage != null && _mineResponse == null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                        ],
                      ),
                    )
                  else ...[
                    // 1. Leave Balance Cards
                    if (_mineResponse != null)
                      LeaveBalanceCards(
                        balance: _mineResponse!.balance,
                        summary: _mineResponse!.summary,
                        totalRequests: _mineResponse!.requests.length,
                      ),
                    const SizedBox(height: 16),

                    // 2. My Leave History
                    if (_mineResponse != null)
                      MyLeaveHistoryWidget(
                        mineData: _mineResponse!,
                        onRefresh: _loadData,
                      ),
                  ],
                ],

                // ==================== ADMIN / MENTOR VIEW ====================
                if (canApproveLeave) ...[
                  const ManageLeaveQueueWidget(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
