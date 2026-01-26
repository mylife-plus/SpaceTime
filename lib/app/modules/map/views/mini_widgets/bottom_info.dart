import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
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

      final memoryRepository = Get.find<FilterController>();
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
    final screenHeight = MediaQuery.of(context).size.height;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        // Swipe down to dismiss
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
        }
      },
      onTap: () {}, // Prevent taps from passing through to background
      child: Container(
        height: screenHeight * 0.3, // 40% of screen height (reduced from fixed 500)
        width: double.infinity,
        decoration: BoxDecoration(
          color: controller2.darkMode.value ? Colors.black : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(0),
            topRight: Radius.circular(0),
          ),
          boxShadow: [
            BoxShadow(
              color: controller2.darkMode.value ? Colors.white30 : Colors.black26,
              blurRadius: 0,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Container(
            height: screenHeight * 0.3,
            child: Column(
              children: [
                // Drag handle indicator
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: controller2.darkMode.value
                          ? Colors.white30
                          : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _memories.isEmpty
                          ? Center(
                              child: Text(
                                'No memories found',
                                style: GoogleFonts.kumbhSans(
                                  color: controller2.darkMode.value ? Colors.white : Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
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
                                    padding: const EdgeInsets.only(top: 2.0, right: 8.0),
                                    child: GestureDetector(
                                      onTap: () => _viewAllMemories(context),
                                      child: Text(
                                        'View',
                                        style: GoogleFonts.kumbhSans(
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
            
                                // Total Memories Count
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                                  child: GestureDetector(
                                    onTap: () => _viewAllMemories(context),
                                    child: Text(
                                      'all ${_memories.length} Memories',
                                      style: GoogleFonts.kumbhSans(
                                        color: const Color(0xFF0071FF),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                Divider(),
            
                                // Display memories grouped intelligently
                                ..._buildMemoryGroups(controller2, context),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
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
        c1.handleFilterApplyFromMap(memoryIds: memoryIdInt);
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
    // Get all unique years from memories using the 'year' field
    final years = _memories
        .map((m) {
          final yearStr = m['year'] as String?;
          if (yearStr == null || yearStr.isEmpty) return null;
          try {
            return int.parse(yearStr);
          } catch (e) {
            debugPrint('[BottomPanel] Error parsing year: $yearStr');
            return null;
          }
        })
        .whereType<int>()
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a)); // Sort descending (newest first)

    debugPrint('[BottomPanel] Found ${years.length} unique years: $years');

    // Always group by year first
    return _buildYearGroups(controller2, years, context);
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
        final yearStr = m['year'] as String?;
        if (yearStr == null || yearStr.isEmpty) return false;
        try {
          return int.parse(yearStr) == year;
        } catch (e) {
          return false;
        }
      }).toList();

      debugPrint('[BottomPanel] Year $year has ${memoriesInYear.length} memories');

      widgets.add(
        GestureDetector(
          onTap: () => _viewMemoriesSubset(context, memoriesInYear),
          child: Text(
            '${memoriesInYear.length} from $year',
            style: GoogleFonts.kumbhSans(
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: controller2.darkMode.value ? Colors.white : Colors.black,
            ),
          ),
        ),
      );
      widgets.add(                            Divider());
      // widgets.add(const SizedBox(height: 4));
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
            style: GoogleFonts.kumbhSans(
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: controller2.darkMode.value ? Colors.white : Colors.black,
            ),
          ),
        ),
      );
      widgets.add(Divider());
      // widgets.add(const SizedBox(height: 4));
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

    // Apply filter logic to show subset of memories
    final c1 = Get.find<MapControllerNew>();
    List<int> memoryIdInt = [];

    for (var memory in memoryLocations) {
      memoryIdInt.add(int.parse(memory.id));
    }

    // Apply filter with the memory IDs
    if (memoryIdInt.isNotEmpty) {
      controller.applyFilters(memoryIds: memoryIdInt);
      await c1.loadFilteredMemoriesFromDB();
      c1.handleFilterApplyFromMap(memoryIds: memoryIdInt);
      debugPrint('[BottomPanel] 🎯 Applied memory IDs filter for subset: $memoryIdInt');
    }

    await Get.toNamed(Routes.ADD_MEMORIES);
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


