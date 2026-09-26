import 'package:flutter/material.dart';

class AppSpacing {
  static const double p4 = 4.0;
  static const double p8 = 8.0;
  static const double p12 = 12.0;
  static const double p16 = 16.0;
  static const double p20 = 20.0;
  static const double p24 = 24.0;
  static const double p32 = 32.0;
  static const double p40 = 40.0;

  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;
  static const double r28 = 28.0;
  static const double r32 = 32.0;
  static const double rPill = 999.0;

  // Semantic radii
  static const double rInput = r16;
  static const double rTile = r20;
  static const double rCard = r24;
  static const double rHero = r28;
}

/// The design is flat: cards sit on the canvas without borders, with at most
/// one very light shadow. No colored glows.
class AppShadows {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// For floating elements such as the center nav button and bottom sheets.
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}
