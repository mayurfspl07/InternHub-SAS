import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
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
  String _activeTab = 'my_leaves'; // 'my_leaves' or 'apply'

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

  void _openApplyDialog() {
    final mine = _mineResponse;
    if (mine == null) {
      // Without the real balance the dialog can't check the request; load it first.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your leave balance is still loading. Try again in a moment.')),
      );
      _loadData();
      return;
    }
    ApplyLeaveDialog.show(
      context,
      balance: mine.balance,
      onSuccess: _loadData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    final canRequestLeave = user.role == UserRole.intern;
    final canApproveLeave =
        user.role == UserRole.admin || user.role == UserRole.mentor || user.role == UserRole.superadmin;


    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Page Header Row (Minimal matching reference)
                PageHeader(
                  title: 'Leave',
                  padding: EdgeInsets.zero,
                  actions: [
                    HeaderAction(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: _loadData),
                  ],
                ),
                const SizedBox(height: 16),

                // Segmented Pills [My Leaves] [Apply] (Screen 4 in Reference UI)
                if (canRequestLeave) ...[
                  Row(
                    children: [
                      _buildPillTab('My Leaves', 'my_leaves'),
                      const SizedBox(width: 10),
                      _buildPillTab('Apply', 'apply', onTap: _openApplyDialog),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

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
                    // 1. Leave balance from the API
                    if (_mineResponse != null)
                      LeaveBalanceCards(
                        balance: _mineResponse!.balance,
                        summary: _mineResponse!.summary,
                        totalRequests: _mineResponse!.requests.length,
                      ),
                    const SizedBox(height: 20),

                    // Full-Width Purple Pill Apply Leave Button (Screen 4 in Reference UI)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _openApplyDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_rounded, size: 20, color: AppColors.onPrimary),
                            const SizedBox(width: 8),
                            Text(
                              'Apply Leave',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

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

  Widget _buildPillTab(String label, String tabKey, {VoidCallback? onTap}) {
    final isSelected = _activeTab == tabKey;
    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap();
        } else {
          setState(() {
            _activeTab = tabKey;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
