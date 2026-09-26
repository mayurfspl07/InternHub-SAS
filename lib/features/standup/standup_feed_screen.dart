import 'package:flutter/material.dart';
import 'standup_screen.dart';

export 'standup_screen.dart';

/// Legacy alias for [StandupScreen]
class StandupFeedScreen extends StatelessWidget {
  final bool showBackButton;
  const StandupFeedScreen({super.key, this.showBackButton = true});

  @override
  Widget build(BuildContext context) {
    return StandupScreen(showBackButton: showBackButton);
  }
}
