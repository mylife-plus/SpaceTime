import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HashtagGroupsController extends GetxController {
  final TextEditingController editController = TextEditingController();
  final RxBool isEditing = false.obs;
  final RxString editingItem = ''.obs;
  final RxString originalItem = ''.obs;
  final RxList<String> sportHashtags =
      <String>[
        'football',
        'basketball',
        'tennis',
        'swimming',
        'running',
        'cycling',
      ].obs;

  @override
  void onInit() {
    super.onInit();
    ever(isEditing, (editing) {
      if (editing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          editController.text = editingItem.value;
          editController.selection = TextSelection.fromPosition(
            TextPosition(offset: editController.text.length),
          );
        });
      }
    });
  }

  void startEditing(String item) {
    originalItem.value = item;
    editingItem.value = item;
    isEditing.value = true;
  }

  void cancelEditing() {
    isEditing.value = false;
    editingItem.value = '';
    originalItem.value = '';
  }

  void saveEditedItem(String newValue) {
    if (newValue.trim().isNotEmpty) {
      final oldItem = originalItem.value;
      final index = sportHashtags.indexOf(oldItem);
      if (index != -1) {
        sportHashtags[index] = newValue.trim();
      }
    }
    cancelEditing();
  }

  @override
  void onClose() {
    editController.dispose();
    super.onClose();
  }
}
