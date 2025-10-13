import 'package:flutter/material.dart';

class AppFonts {
  static const String fontFamily = 'KumbhSans';

  static TextStyle regular(double size, {Color color = Colors.black}) {
    return TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w400,
      fontSize: size,
      color: color,
    );
  }

  static TextStyle light(double size, {Color color = Colors.black}) {
    return TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w300,
      fontSize: size,
      color: color,
    );
  }

  static TextStyle medium(double size, {Color color = Colors.black}) {
    return TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w500,
      fontSize: size,
      color: color,
    );
  }
}
