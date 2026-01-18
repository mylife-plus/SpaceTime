import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/routes/app_pages.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/repositories/memory_repository.dart';
import 'package:spacetime/services/memory_clustering_service.dart' as clustering;
import '../../controllers/map_controller_new.dart';

class BottomPanel extends StatefulWidget {
  final List<String> memoryIds;

  const BottomPanel({
    super.key,
    required this.memoryIds,
  });

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  List<Map<String, dynamic>> _memories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMemories();
  }

  /// Fetch memories from database using the provided memory IDs
  Future<void> _fetchMemories() async {
    try {
      debugPrint('[BottomPanel] Fetching ${widget.memoryIds.length} memories from database...');

      final memoryRepository = Get.find<MemoryRepository>();
      final allMemories = memoryRepository.allMemories;

      // Filter memories by the provided IDs
      final fetchedMemories = <Map<String, dynamic>>[];
      for (final memoryId in widget.memoryIds) {
        final memory = allMemories.firstWhereOrNull(
          (m) => m['id']?.toString() == memoryId,
        );
        if (memory != null) {
          fetchedMemories.add(memory);
        } else {
          debugPrint('[BottomPanel] ⚠️ Memory with ID $memoryId not found');
        }
      }

      debugPrint('[BottomPanel] ✅ Fetched ${fetchedMemories.length} memories');

      setState(() {
        _memories = fetchedMemories;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[BottomPanel] ❌ Error fetching memories: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller2 = Get.find<UiController>();

    return Container(
      height: 500,
      width: double.infinity,
      decoration: BoxDecoration(
        color: controller2.darkMode.value ? Colors.black : Colors.white,
        boxShadow: [
          BoxShadow(
            color: controller2.darkMode.value ? Colors.white30 : Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? Center(
                  child: Text(
                    'No memories found',
                    style: TextStyle(
                      color: controller2.darkMode.value ? Colors.white : Colors.black,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // View All Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                        child: GestureDetector(
                          onTap: () => _viewAllMemories(context),
                          child: Text(
                            'View',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: controller2.darkMode.value
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(),

                    // Total Memories Count
                    GestureDetector(
                      onTap: () => _viewAllMemories(context),
                      child: Text(
                        'all ${_memories.length} Memories',
                        style: const TextStyle(
                          color: Color(0xFF0071FF),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Divider(),

                    // Display memories grouped intelligently
                    ..._buildMemoryGroups(controller2, context),
                  ],
                ),
    );
  }

  /// Navigate to view all memories
  Future<void> _viewAllMemories(BuildContext context) async {
    final controller = Get.find<AddMemoriesController>();
    Navigator.of(context).pop();

    // Convert memories to MemoryLocation objects for showSpecificMemories
    final memoryLocations = _memories
        .map((memory) {
          try {
            return clustering.MemoryLocation.fromMap(memory);
          } catch (e) {
            debugPrint('[BottomPanel] ⚠️ Failed to create MemoryLocation from: ${memory['id']} - $e');
            return null;
          }
        })
        .where((memoryLocation) => memoryLocation != null)
        .cast<clustering.MemoryLocation>()
        .toList();

    debugPrint('[BottomPanel] Converted ${memoryLocations.length} memories to MemoryLocation objects');

    final c1 = Get.find<MapControllerNew>();
      List<int> memoryIdInt = [];

      for(var memory in memoryLocations){

        memoryIdInt.add(int.parse(memory.id));
      }
      // Show the specific memory in AddMemories view
      // controller.showSpecificMemories([memoryLocation]);

      // Apply filter with the memory ID
      // final memoryIdInt = int.tryParse(memoryId);
      if (memoryIdInt.isNotEmpty) {
      controller.applyFilters(memoryIds: memoryIdInt);
        await c1.loadFilteredMemoriesFromDB();
        c1.handleFilterApplyFromMap();
        debugPrint('[MapControllerNew] 🎯 Applied memory IDs filter: [$memoryIdInt]');
      }

      // debugPrint('[MapControllerNew] 🎯 Navigating to AddMemories view with memory: ${foundMemory['category'] ?? foundMemory['description']}');

      final result = await Get.toNamed(Routes.ADD_MEMORIES);
    // Use showSpecificMemories which properly handles the data
    // controller.showSpecificMemories(memoryLocations);
    // final result = await Get.toNamed(Routes.ADD_MEMORIES);

    // // If memories were edited/deleted, refresh the map
    // if (result == true) {
    //   try {
    //     final mapController = Get.find<MapControllerNew>();
    //     await mapController.refreshMapView();
    //     debugPrint('[BottomPanel] Map refreshed after memory editing');
    //   } catch (e) {
    //     debugPrint('[BottomPanel] MapControllerNew not found: $e');
    //   }
    // }
  }

  /// Build memory groups based on year/month
  List<Widget> _buildMemoryGroups(
    UiController controller2,
    BuildContext context,
  ) {
    // Get all unique years from memories
    final years = _memories
        .map((m) {
          final dateStr = m['date'] as String?;
          if (dateStr == null) return null;
          try {
            return DateTime.parse(dateStr).year;
          } catch (e) {
            return null;
          }
        })
        .whereType<int>()
        .toSet()
        .toList();
    years.sort();

    // If memories span multiple years, group by year
    if (years.length > 1) {
      return _buildYearGroups(controller2, years, context);
    } else if (years.isNotEmpty) {
      // If all memories are from the same year, group by month
      return _buildMonthGroups(controller2, years.first, context);
    }

    return [];
  }

  /// Build year groups
  List<Widget> _buildYearGroups(
    UiController controller2,
    List<int> years,
    BuildContext context,
  ) {
    final widgets = <Widget>[];

    for (final year in years) {
      final memoriesInYear = _memories.where((m) {
        final dateStr = m['date'] as String?;
        if (dateStr == null) return false;
        try {
          return DateTime.parse(dateStr).year == year;
        } catch (e) {
          return false;
        }
      }).toList();

      widgets.add(
        GestureDetector(
          onTap: () => _viewMemoriesSubset(context, memoriesInYear),
          child: Text(
            '${memoriesInYear.length} memories from $year',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: controller2.darkMode.value ? Colors.white : Colors.black,
            ),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 4));
    }

    return widgets;
  }

  /// Build month groups
  List<Widget> _buildMonthGroups(
    UiController controller2,
    int year,
    BuildContext context,
  ) {
    // Group memories by month
    final monthGroups = <int, List<Map<String, dynamic>>>{};

    for (final memory in _memories) {
      final dateStr = memory['date'] as String?;
      if (dateStr == null) continue;

      try {
        final date = DateTime.parse(dateStr);
        if (date.year == year) {
          final month = date.month;
          monthGroups[month] = monthGroups[month] ?? [];
          monthGroups[month]!.add(memory);
        }
      } catch (e) {
        debugPrint('[BottomPanel] Error parsing date: $dateStr');
      }
    }

    final months = monthGroups.keys.toList();
    months.sort();

    final widgets = <Widget>[];

    for (final month in months) {
      final memoriesInMonth = monthGroups[month]!;
      final monthName = _getMonthName(month);

      widgets.add(
        GestureDetector(
          onTap: () => _viewMemoriesSubset(context, memoriesInMonth),
          child: Text(
            '${memoriesInMonth.length} memories from $monthName $year',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: controller2.darkMode.value ? Colors.white : Colors.black,
            ),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 4));
    }

    return widgets;
  }

  /// View a subset of memories
  Future<void> _viewMemoriesSubset(
    BuildContext context,
    List<Map<String, dynamic>> memories,
  ) async {
    final controller = Get.find<AddMemoriesController>();
    Navigator.of(context).pop();

    // Convert memories to MemoryLocation objects for showSpecificMemories
    final memoryLocations = memories
        .map((memory) {
          try {
            return clustering.MemoryLocation.fromMap(memory);
          } catch (e) {
            debugPrint('[BottomPanel] ⚠️ Failed to create MemoryLocation from: ${memory['id']} - $e');
            return null;
          }
        })
        .where((memoryLocation) => memoryLocation != null)
        .cast<clustering.MemoryLocation>()
        .toList();

    debugPrint('[BottomPanel] Converted ${memoryLocations.length} memories to MemoryLocation objects for subset');

    // Use showSpecificMemories which properly handles the data
    final c1 = Get.find<MapControllerNew>();
      List<int> memoryIdInt = [];

      for(var memory in memoryLocations){

        memoryIdInt.add(int.parse(memory.id));
      }
      // Show the specific memory in AddMemories view
      // controller.showSpecificMemories([memoryLocation]);

      // Apply filter with the memory ID
      // final memoryIdInt = int.tryParse(memoryId);
      if (memoryIdInt.isNotEmpty) {
      controller.applyFilters(memoryIds: memoryIdInt);
        await c1.loadFilteredMemoriesFromDB();
        c1.handleFilterApplyFromMap();
        debugPrint('[MapControllerNew] 🎯 Applied memory IDs filter: [$memoryIdInt]');
      }

      // debugPrint('[MapControllerNew] 🎯 Navigating to AddMemories view with memory: ${foundMemory['category'] ?? foundMemory['description']}');

      final result = await Get.toNamed(Routes.ADD_MEMORIES);
  }



  /// Get month name from month number
  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }
}


