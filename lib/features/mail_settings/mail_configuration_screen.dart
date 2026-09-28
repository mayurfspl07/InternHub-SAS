import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import 'mail_repository.dart';
import 'models/mail_models.dart';
import 'widgets/mail_config_panel.dart';
import 'widgets/mail_logs_panel.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';

class MailConfigurationScreen extends ConsumerStatefulWidget {
  const MailConfigurationScreen({super.key});

  @override
  ConsumerState<MailConfigurationScreen> createState() => _MailConfigurationScreenState();
}

class _MailConfigurationScreenState extends ConsumerState<MailConfigurationScreen>
    with SingleTickerProviderStateMixin {
  final MailRepository _repository = MailRepository();

  late TabController _tabController;
  int _activeTab = 0;
  bool _isLoading = true;
  String? _errorMessage;
  OrgSmtpConfig? _config;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index != _activeTab) {
        setState(() => _activeTab = _tabController.index);
      }
    });
    _loadConfig();
  }

  Widget _buildSegmentedTab(String label, int index) {
    final isSelected = _activeTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = index;
          _tabController.animateTo(index);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.getSmtpConfig();
      if (mounted) {
        setState(() {
          _config = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = apiErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  bool _canManageMailSettings(UserRole role) {
    return role == UserRole.admin || role == UserRole.superadmin;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appStateProvider).currentUser;
    final cardBg = AppColors.surface;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    // Permission check
    if (!_canManageMailSettings(user.role)) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: pageAppBar(context, title: 'Mail configuration'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_outline_rounded, size: 28, color: AppColors.danger),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Access Restricted',
                    style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You don\'t have permission to manage mail configuration for this organization.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(color: secondaryTextColor),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/dashboard');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Back to Dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Mail configuration',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppSpacing.rPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSegmentedTab('Configuration', 0),
                            _buildSegmentedTab('Delivery log', 1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
          // TAB 1: CONFIGURATION
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage != null)
            LoadErrorView(title: "Couldn't load mail settings", message: _errorMessage!, onRetry: _loadConfig)
          else
            MailConfigPanel(
              initialConfig: _config!,
              repository: _repository,
              onConfigUpdated: (updated) {
                setState(() {
                  _config = updated;
                });
              },
            ),

          // TAB 2: DELIVERY LOGS
          MailLogsPanel(repository: _repository),
        ],
      ),
    ),
  ],
),
),
);
  }
}
