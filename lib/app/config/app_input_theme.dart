import 'package:flutter/material.dart';

/// Shared input metrics so single-line [TextField]s match unless a widget
/// passes its own [InputDecoration.contentPadding] (which overrides theme).
abstract final class AppInputTheme {
  static const EdgeInsets singleLineContentPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  static const InputDecorationTheme singleLineDecorationTheme =
      InputDecorationTheme(
    isDense: true,
    contentPadding: singleLineContentPadding,
  );
}
