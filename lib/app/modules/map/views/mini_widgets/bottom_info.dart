import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/routes/app_pages.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
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

  Future<void> _fetchMemories() async {
    try {
      final filterController = Get.find<FilterController>();
      final allMemories = filterController.allMemories;

      final fetched = <Map<String, dynamic>>[];
      for (final id in widget.memoryIds) {
        final m = allMemories.firstWhereOrNull(
          (e) => e['id']?.toString() == id,
        );
        if (m != null) fetched.add(m);
      }

      setState(() {
        _memories = fetched;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = Get.find<UiController>();
    final screenHeight = MediaQuery.of(context).size.height;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.7, // ⬅️ MAX HEIGHT
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: ui.darkMode.value ? Colors.black : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: ui.darkMode.value
                        ? Colors.white30
                        : Colors.black26,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // 🔑 content-driven height
                  children: [
                    // Drag handle
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 12),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ui.darkMode.value
                              ? Colors.white30
                              : Colors.black26,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      )
                    else if (_memories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No memories found',
                          style: GoogleFonts.kumbhSans(
                            fontSize: 16,
                            decoration: TextDecoration.none,
                            color: ui.darkMode.value
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                           
                            // const SizedBox(height: 8),

                            GestureDetector(
                              onTap: () => _viewAllMemories(context),
                              child: Text(
                                'All ${_memories.length} Memories',
                                style: GoogleFonts.kumbhSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                  color: const Color(0xFF0071FF),
                                ),
                              ),
                            ),

                            const Divider(height: 10),

                            ..._buildYearGroups(ui, context),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildYearGroups(UiController ui, BuildContext context) {
    final years = _memories
        .map((m) => int.tryParse(m['year'] ?? ''))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final yearMemories =
          _memories.where((m) => m['year'] == year.toString()).toList();

      return Column(
        children: [
          GestureDetector(
            onTap: () => _viewMemoriesSubset(context, yearMemories),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 0),
              child: Text(
                '${yearMemories.length} from $year',
                style: GoogleFonts.kumbhSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                  color:
                      ui.darkMode.value ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
          const Divider(),
        ],
      );
    }).toList();
  }

  Future<void> _viewAllMemories(BuildContext context) async {
    Navigator.of(context).pop();
    await Get.toNamed(Routes.ADD_MEMORIES);
  }

  Future<void> _viewMemoriesSubset(
    BuildContext context,
    List<Map<String, dynamic>> memories,
  ) async {
    Navigator.of(context).pop();
    await Get.toNamed(Routes.ADD_MEMORIES);
  }
}
