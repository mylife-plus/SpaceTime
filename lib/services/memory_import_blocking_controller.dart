import 'package:get/get.dart';

/// When true, [MemoryImportBlockingOverlay] blocks all navigation and taps app-wide.
class MemoryImportBlockingController extends GetxController {
  final RxBool importing = false.obs;
}
