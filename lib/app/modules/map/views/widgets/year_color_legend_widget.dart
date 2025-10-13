import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class YearColorLegendWidget extends StatelessWidget {
  final int? selectedYear;
  final Function(int)? onYearSelected;
  final bool showAllYears;
  final int yearsToShow;

  const YearColorLegendWidget({
    super.key,
    this.selectedYear,
    this.onYearSelected,
    this.showAllYears = false,
    this.yearsToShow = 10,
  });

  @override
  Widget build(BuildContext context) {
    final mapController = Get.find<MapController>();
    final uiController = Get.find<UiController>();
    final currentYear = DateTime.now().year;

    return Obx(
      () => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              uiController.darkMode.value
                  ? Colors.black.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Year Color Legend',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color:
                    uiController.darkMode.value ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            if (showAllYears)
              _buildAllYearsGrid(mapController, uiController, currentYear)
            else
              _buildRecentYearsList(mapController, uiController, currentYear),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentYearsList(
    MapController mapController,
    UiController uiController,
    int currentYear,
  ) {
    final startYear = currentYear - (yearsToShow ~/ 2);
    final endYear = currentYear + (yearsToShow ~/ 2);

    return Column(
      children: List.generate(endYear - startYear + 1, (index) {
        final year = startYear + index;
        final color = mapController.getColorForYear(year);
        final isSelected = selectedYear == year;
        final isCurrent = year == currentYear;

        return GestureDetector(
          onTap: () => onYearSelected?.call(year),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? color.withValues(alpha: 0.2)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: color, width: 2) : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  year.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color:
                        uiController.darkMode.value
                            ? Colors.white
                            : Colors.black,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'NOW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAllYearsGrid(
    MapController mapController,
    UiController uiController,
    int currentYear,
  ) {
    final yearColorMap = mapController.getYearColorMappings(
      startYear: -50,
      endYear: 50,
    );
    final sortedYears = yearColorMap.keys.toList()..sort();

    return SizedBox(
      height: 300,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              sortedYears.map((year) {
                final color = yearColorMap[year]!;
                final isSelected = selectedYear == year;
                final isCurrent = year == currentYear;

                return GestureDetector(
                  onTap: () => onYearSelected?.call(year),
                  child: Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : Border.all(
                                color:
                                    uiController.darkMode.value
                                        ? Colors.white.withValues(alpha: 0.3)
                                        : Colors.black.withValues(alpha: 0.3),
                                width: 1,
                              ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            year.toString(),
                            style: TextStyle(
                              fontSize: isCurrent ? 12 : 10,
                              fontWeight:
                                  isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                              color: Colors.white,
                              shadows: const [
                                Shadow(
                                  offset: Offset(1, 1),
                                  blurRadius: 2,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            const Text(
                              'NOW',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    offset: Offset(1, 1),
                                    blurRadius: 2,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }
}

class YearColorIndicator extends StatelessWidget {
  final int year;
  final double size;
  final bool showYear;

  const YearColorIndicator({
    super.key,
    required this.year,
    this.size = 24,
    this.showYear = true,
  });

  @override
  Widget build(BuildContext context) {
    final mapController = Get.find<MapController>();
    final color = mapController.getColorForYear(year);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child:
          showYear && size >= 30
              ? Center(
                child: Text(
                  year.toString().substring(2), // Show last 2 digits
                  style: TextStyle(
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 2,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              )
              : null,
    );
  }
}
