// import 'package:flutter/services.dart';

// /// Helper class to manage device orientation throughout the app
// class OrientationHelper {
//   /// Lock orientation to portrait only
//   static Future<void> lockPortrait() async {
//     await SystemChrome.setPreferredOrientations([
//       DeviceOrientation.portraitUp,
//       DeviceOrientation.portraitDown,
//     ]);
//   }

//   /// Lock orientation to landscape only
//   static Future<void> lockLandscape() async {
//     await SystemChrome.setPreferredOrientations([
//       DeviceOrientation.landscapeLeft,
//       DeviceOrientation.landscapeRight,
//     ]);
//   }

//   /// Allow all orientations
//   static Future<void> allowAllOrientations() async {
//     await SystemChrome.setPreferredOrientations([
//       DeviceOrientation.portraitUp,
//       DeviceOrientation.portraitDown,
//       DeviceOrientation.landscapeLeft,
//       DeviceOrientation.landscapeRight,
//     ]);
//   }

//   /// Lock to portrait up only (most restrictive)
//   static Future<void> lockPortraitUp() async {
//     await SystemChrome.setPreferredOrientations([
//       DeviceOrientation.portraitUp,
//     ]);
//   }

//   /// Reset to app default (portrait only)
//   static Future<void> resetToDefault() async {
//     await lockPortrait();
//   }
// }

// /// Mixin to easily add orientation control to any StatefulWidget
// mixin OrientationControlMixin<T extends StatefulWidget> on State<T> {
//   /// Override this to set the desired orientation for this screen
//   List<DeviceOrientation> get allowedOrientations => [
//     DeviceOrientation.portraitUp,
//     DeviceOrientation.portraitDown,
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _setOrientation();
//   }

//   @override
//   void dispose() {
//     // Reset to default orientation when leaving the screen
//     OrientationHelper.resetToDefault();
//     super.dispose();
//   }

//   void _setOrientation() {
//     SystemChrome.setPreferredOrientations(allowedOrientations);
//   }
// }
