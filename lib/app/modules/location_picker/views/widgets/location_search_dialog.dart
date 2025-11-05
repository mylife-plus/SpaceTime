import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/location_picker/controllers/location_picker_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class LocationSearchDialog extends StatefulWidget {
  final LocationPickerController controller;

  const LocationSearchDialog({
    super.key,
    required this.controller,
  });

  @override
  State<LocationSearchDialog> createState() => _LocationSearchDialogState();
}

class _LocationSearchDialogState extends State<LocationSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final UiController uiController = Get.find<UiController>();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildSearchField(),
            Flexible(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  /// Build dialog header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: uiController.darkMode.value ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Search Locations',
              style: AppFonts.medium(
                18,
                color: uiController.darkMode.value ? Colors.white : Colors.black,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: uiController.darkMode.value ? Colors.white : Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Build search field
  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: AppFonts.regular(
          16,
          color: uiController.darkMode.value ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: 'Search for a location...',
          hintStyle: AppFonts.regular(
            16,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    widget.controller.searchLocations('');
                    setState(() {});
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: uiController.darkMode.value ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: uiController.darkMode.value ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: uiController.currentMainColor,
              width: 2,
            ),
          ),
          filled: true,
          fillColor: uiController.darkMode.value 
              ? Colors.grey[800] 
              : Colors.grey[50],
        ),
        onChanged: (value) {
          widget.controller.searchLocations(value);
          setState(() {});
        },
      ),
    );
  }

  /// Build dialog content
  Widget _buildContent() {
    return Obx(() {
      if (widget.controller.isSearching.value) {
        return _buildLoadingView();
      }

      if (widget.controller.searchQuery.value.isEmpty) {
        return _buildRecentLocations();
      }

      if (widget.controller.searchResults.isEmpty) {
        return _buildNoResultsView();
      }

      return _buildSearchResults();
    });
  }

  /// Build loading view
  Widget _buildLoadingView() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// Build recent locations
  Widget _buildRecentLocations() {
    if (widget.controller.recentLocations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No recent locations',
            style: AppFonts.regular(
              16,
              color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: widget.controller.recentLocations.length,
      itemBuilder: (context, index) {
        final location = widget.controller.recentLocations[index];
        return _buildLocationTile(
          title: location.address,
          subtitle: '${location.city}${location.city.isNotEmpty && location.state.isNotEmpty ? ', ' : ''}${location.state}',
          onTap: () {
            widget.controller.selectSearchResult({
              'latitude': location.latitude,
              'longitude': location.longitude,
              'name': location.address,
              'city': location.city,
              'region': location.state,
              'country': location.country,
            });
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  /// Build search results
  Widget _buildSearchResults() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: widget.controller.searchResults.length,
      itemBuilder: (context, index) {
        final result = widget.controller.searchResults[index];
        return _buildLocationTile(
          title: result['name'] ?? 'Unknown Location',
          subtitle: result['address'] ?? '',
          onTap: () {
            widget.controller.selectSearchResult(result);
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  /// Build no results view
  Widget _buildNoResultsView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
            ),
            const SizedBox(height: 16),
            Text(
              'No locations found',
              style: AppFonts.medium(
                16,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: AppFonts.regular(
                14,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build location tile
  Widget _buildLocationTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        Icons.location_on,
        color: uiController.currentMainColor,
      ),
      title: Text(
        title,
        style: AppFonts.medium(
          16,
          color: uiController.darkMode.value ? Colors.white : Colors.black,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: AppFonts.regular(
                14,
                color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
