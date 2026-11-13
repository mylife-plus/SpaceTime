import 'package:get/get.dart';

/// When true, [MemoryImportBlockingOverlay] blocks all navigation and taps app-wide.
class MemoryImportBlockingController extends GetxController {
  final RxBool importing = false.obs;

  /// Optional progress line under the spinner (e.g. "12 / 47").
  final RxString progressLabel = ''.obs;

  void beginImport({String progress = ''}) {
    progressLabel.value = progress;
    importing.value = true;
  }

  void setProgress(String label) {
    progressLabel.value = label;
  }

  void endImport() {
    importing.value = false;
    progressLabel.value = '';
  }
}
