import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/routes/app_pages.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/services/memory_clustering_service.dart';
import '../../controllers/map_controller_new.dart';

class BottomPanel extends StatelessWidget {
  final MemoryCluster cluster;
  final String? selectedYear;
  final List<Map<String, dynamic>>? specificMemories;

  const BottomPanel(
    this.cluster, {
    super.key,
    this.selectedYear,
    this.specificMemories,
  });

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
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 8.0),
              child: GestureDetector(
                onTap: () async {
                  var controller = Get.find<AddMemoriesController>();

                  Navigator.of(context).pop();

                  // Convert MemoryLocation objects to Map<String, dynamic> format
                  //  final memoriesMetadata = memoriesInYearData.map((memoryLocation) => memoryLocation.metadata).toList();

                  controller.showSpecificMemories(cluster.memories);

                  final result = await Get.toNamed(Routes.ADD_MEMORIES);

                  // If memories were edited/deleted, refresh the map
                  if (result == true) {
                    try {
                      final mapController = Get.find<MapControllerNew>();
                      await mapController.refreshLocation();();
                      debugPrint(
                        'Map refreshed after memory editing from cluster view',
                      );
                    } catch (e) {
                      debugPrint('MapControllerNew not found: $e');
                    }
                  }
                },
                child: Text(
                  'View',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color:
                        controller2.darkMode.value
                            ? Colors.white
                            : Colors.black,
                  ),
                ),
              ),
            ),
          ),
          const Divider(),
          GestureDetector(
            onTap: () async {
              Navigator.of(context).pop();
              var controller = Get.find<AddMemoriesController>();

              // Convert MemoryLocation objects to Map<String, dynamic> format
              //  final memoriesMetadata = memoriesInYearData.map((memoryLocation) => memoryLocation.metadata).toList();

              controller.showSpecificMemories(cluster.memories);

              final result = await Get.toNamed(Routes.ADD_MEMORIES);

              // If memories were edited/deleted, refresh the map
              if (result == true) {
                try {
                  final mapController = Get.find<MapControllerNew>();
                  await mapController.refreshMapView();
                  debugPrint(
                    'Map refreshed after memory editing from cluster view',
                  );
                } catch (e) {
                  debugPrint('MapControllerNew not found: $e');
                }
              }
            },
            child: Text(
              'all ${cluster.memoryCount} Memories',
              style: TextStyle(
                color: const Color(0xFF0071FF),
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
          const Divider(),
          // Display memories grouped intelligently
          ..._buildMemoryGroups(cluster, controller2, context),
        ],
      ),
    );
  }

  List<Widget> _buildMemoryGroups(
    MemoryCluster cluster,
    UiController controller2,
    BuildContext context,
  ) {
    // Get all unique years from memories
    final years =
        cluster.memories.map((m) => m.memoryDate.year).toSet().toList();
    years.sort();

    // If memories span multiple years, group by year
    if (years.length > 1) {
      return _buildYearGroups(cluster, controller2, years, context);
    } else {
      // If all memories are from the same year, group by month
      return _buildMonthGroups(cluster, controller2, years.first, context);
    }
  }

  List<Widget> _buildYearGroups(
    MemoryCluster cluster,
    UiController controller2,
    List<int> years,
    BuildContext context,
  ) {
    List<Widget> widgets = [];

    for (final year in years) {
      final memoriesInYearData =
          cluster.memories.where((m) => m.memoryDate.year == year).toList();
      final memoriesInYear = memoriesInYearData.length;

      widgets.add(
        GestureDetector(
          onTap: () {
            var controller = Get.find<AddMemoriesController>();

            // Convert MemoryLocation objects to Map<String, dynamic> format
            final memoriesMetadata =
                memoriesInYearData
                    .map((memoryLocation) => memoryLocation.metadata)
                    .toList();

            Navigator.of(context).pop();

            controller.showSpecificMemories(memoriesInYearData);

            Get.toNamed(Routes.ADD_MEMORIES);
          },
          child: Text(
            '$memoriesInYear memories from $year',
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

  List<Widget> _buildMonthGroups(
    MemoryCluster cluster,
    UiController controller2,
    int year,
    BuildContext context,
  ) {
    // Group memories by month
    final monthGroups = <int, List<MemoryLocation>>{};

    for (final memory in cluster.memories) {
      final month = memory.memoryDate.month;
      monthGroups[month] = monthGroups[month] ?? [];
      monthGroups[month]!.add(memory);
    }

    final months = monthGroups.keys.toList();
    months.sort();

    List<Widget> widgets = [];

    for (final month in months) {
      final memoriesInMonth = monthGroups[month]!.length;
      final monthName = _getMonthName(month);
      final memoriesInMonthData = monthGroups[month]!;

      widgets.add(
        GestureDetector(
          onTap: () {
            var controller = Get.find<AddMemoriesController>();

            final memoriesMetadata =
                memoriesInMonthData
                    .map((memoryLocation) => memoryLocation.metadata)
                    .toList();

            Navigator.of(context).pop();

            controller.showSpecificMemories(memoriesInMonthData);

            Get.toNamed(Routes.ADD_MEMORIES);
          },
          child: Text(
            '$memoriesInMonth memories from $monthName $year',
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

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class BottomPanel1 extends StatelessWidget {
  final String? selectedYear;

  const BottomPanel1(MemoryCluster cluster, {super.key, this.selectedYear});

  void _navigateToMemoriesWithFilter(String? year) {
    // Get or create the AddMemoriesController
    // final controller = Get.put(AddMemoriesController());

    // if (year != null) {
    //   // Set the search query to filter by year and force search
    //   controller.searchQuery.value = year;
    //   controller.filterByYear(year);
    // } else {
    //   // Show all memories
    //   controller.seeAllMemories();
    // }

    // Navigate to the add memories screen
    Get.toNamed(Routes.ADD_MEMORIES);
  }

  @override
  Widget build(BuildContext context) {
    final controller2 = Get.find<UiController>();
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: controller2.darkMode.value ? Colors.black : Colors.white,
        boxShadow: [
          BoxShadow(
            color: controller2.darkMode.value ? Colors.white30 : Colors.black26,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 8.0),
              child: GestureDetector(
                onTap: () => _navigateToMemoriesWithFilter(null),
                child: Text(
                  'View',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color:
                        controller2.darkMode.value
                            ? Colors.white
                            : Colors.black,
                  ),
                ),
              ),
            ),
          ),
          const Divider(),
          GestureDetector(
            onTap: () => _navigateToMemoriesWithFilter(selectedYear),
            child: Text(
              selectedYear != null ? '1 from $selectedYear' : 'all 2 Memories',
              style: TextStyle(
                color: const Color(0xFF0071FF),
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
          const Divider(),
          GestureDetector(
            onTap: () => _navigateToMemoriesWithFilter('2025'),
            child: Text(
              '1 from 2025',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: controller2.darkMode.value ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _navigateToMemoriesWithFilter('2024'),
            child: Text(
              '1 from 2024',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: controller2.darkMode.value ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
