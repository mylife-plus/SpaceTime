import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import '../../../ui/controllers/ui_controller.dart';

class MemoryClusterPopup extends StatelessWidget {
  final List<Map<String, dynamic>> memories;
  final Function(Map<String, dynamic>) onMemorySelected;

  const MemoryClusterPopup({
    super.key,
    required this.memories,
    required this.onMemorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    uiController.darkMode.value
                        ? Colors.grey[800]
                        : Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color:
                        uiController.darkMode.value
                            ? Colors.blue[300]
                            : Colors.blue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trKey('text_memories_length_memories_at_this_location', [
                        memories.length,
                      ]),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            uiController.darkMode.value
                                ? Colors.white
                                : Colors.black,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color:
                          uiController.darkMode.value
                              ? Colors.white
                              : Colors.black,
                    ),
                  ),
                ],
              ),
            ),

            // Memory list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: memories.length,
                separatorBuilder:
                    (context, index) => Divider(
                      color:
                          uiController.darkMode.value
                              ? Colors.grey[700]
                              : Colors.grey[300],
                      height: 1,
                    ),
                itemBuilder: (context, index) {
                  final memory = memories[index];
                  return _buildMemoryListItem(memory, uiController);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryListItem(
    Map<String, dynamic> memory,
    UiController uiController,
  ) {
    // Parse date
    DateTime? memoryDate;
    try {
      if (memory['created_at'] != null) {
        memoryDate = DateTime.parse(memory['created_at']);
      }
    } catch (e) {
      // Fallback to current date if parsing fails
      memoryDate = DateTime.now();
    }

    final dateStr =
        memoryDate != null
            ? DateFormat('MMM dd, yyyy • HH:mm').format(memoryDate)
            : 'Unknown date';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color:
              uiController.darkMode.value
                  ? Colors.blue[900]?.withValues(alpha: 0.3)
                  : Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                uiController.darkMode.value
                    ? Colors.blue[600]!
                    : Colors.blue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.memory,
          color:
              uiController.darkMode.value ? Colors.blue[300] : Colors.blue[700],
          size: 24,
        ),
      ),
      title: Text(
        memory['text'] ?? memory['description'] ?? 'Untitled Memory',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: uiController.darkMode.value ? Colors.white : Colors.black,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 12,
              color:
                  uiController.darkMode.value
                      ? Colors.grey[400]
                      : Colors.grey[600],
            ),
          ),
          if (memory['location'] != null &&
              memory['location'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 12,
                    color:
                        uiController.darkMode.value
                            ? Colors.grey[500]
                            : Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatLocation(memory['location'].toString()),
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            uiController.darkMode.value
                                ? Colors.grey[500]
                                : Colors.grey[500],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (memory['tags'] != null && memory['tags'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                trKey('text_memory', [
                  memory['tags'].toString().replaceAll(',', ' #'),
                ]),
                style: TextStyle(
                  fontSize: 11,
                  color:
                      uiController.darkMode.value
                          ? Colors.green[400]
                          : Colors.green[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color:
            uiController.darkMode.value ? Colors.grey[400] : Colors.grey[600],
      ),
      onTap: () => onMemorySelected(memory),
    );
  }

  String _formatLocation(String location) {
    // If location contains coordinates, try to format them nicely
    if (location.contains(',')) {
      final parts = location.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        }
      }
    }
    return location;
  }
}
