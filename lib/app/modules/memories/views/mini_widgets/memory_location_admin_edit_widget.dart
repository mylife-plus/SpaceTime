import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/world_locations_service.dart';

class MemoryLocationAdminEditWidget extends StatefulWidget {
  const MemoryLocationAdminEditWidget({super.key});

  @override
  State<MemoryLocationAdminEditWidget> createState() =>
      _MemoryLocationAdminEditWidgetState();
}

class _MemoryLocationAdminEditWidgetState
    extends State<MemoryLocationAdminEditWidget> {
  final MemoryController _memoryController = Get.find<MemoryController>();
  final UiController _uiController = Get.find<UiController>();

  final TextEditingController _countrySearchController =
      TextEditingController();
  final TextEditingController _stateProvinceController = TextEditingController();
  final TextEditingController _cityTownController = TextEditingController();

  bool _isLoadingCountries = true;
  bool _showCountryDropdown = false;
  List<Country> _filteredCountries = <Country>[];
  Country? _selectedCountry;

  @override
  void initState() {
    super.initState();

    // Pre-fill from existing memory location.
    _stateProvinceController.text = _memoryController.locationAddress.value;
    _cityTownController.text = _memoryController.locationCity.value;
    _countrySearchController.text = _memoryController.locationCountry.value;

    _loadCountriesAndSelectCurrent();
    _countrySearchController.addListener(_onCountrySearchChanged);
  }

  @override
  void dispose() {
    _countrySearchController.removeListener(_onCountrySearchChanged);
    _countrySearchController.dispose();
    _stateProvinceController.dispose();
    _cityTownController.dispose();
    super.dispose();
  }

  Future<void> _loadCountriesAndSelectCurrent() async {
    setState(() {
      _isLoadingCountries = true;
    });

    await WorldLocationsService.instance.initialize();

    final currentCountryName = _memoryController.locationCountry.value;
    final allCountries = WorldLocationsService.instance.countries;

    Country? match;
    final lowerCurrent = currentCountryName.trim().toLowerCase();
    if (lowerCurrent.isNotEmpty) {
      try {
        match = allCountries.firstWhere(
          (c) => c.name.trim().toLowerCase() == lowerCurrent,
        );
      } catch (_) {
        match = null;
      }
    }

    setState(() {
      _selectedCountry = match;
      _filteredCountries = match != null ? <Country>[match] : <Country>[];
      _isLoadingCountries = false;
    });
  }

  void _onCountrySearchChanged() {
    if (_isLoadingCountries) return;

    final query = _countrySearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _showCountryDropdown = false;
        _filteredCountries = _selectedCountry != null
            ? <Country>[_selectedCountry!]
            : <Country>[];
      });
      return;
    }

    if (_selectedCountry != null &&
        query == _selectedCountry!.name.trim().toLowerCase()) {
      setState(() {
        _showCountryDropdown = false;
        _filteredCountries = <Country>[_selectedCountry!];
      });
      return;
    }

    final countries = WorldLocationsService.instance.countries;
    final results = countries
        .where((c) =>
            c.name.toLowerCase().contains(query) ||
            c.code.toLowerCase().contains(query))
        .take(10)
        .toList();

    setState(() {
      _showCountryDropdown = true;
      _filteredCountries = results;
    });
  }

  String _flagFromIso2(String? iso2) {
    if (iso2 == null) return '🌍';
    final code = iso2.trim().toUpperCase();
    if (code.length != 2) return '🌍';

    // Convert ISO-3166 alpha-2 into regional indicator symbols.
    const int offset = 127397;
    final int first = code.codeUnitAt(0) + offset;
    final int second = code.codeUnitAt(1) + offset;
    return String.fromCharCodes([first, second]);
  }

  Widget _buildHeader(bool isDark) {
    final bg = isDark ? Colors.black : const Color(0xFF8EC0F4);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 12,
        right: 12,
        bottom: 10,
      ),
      decoration: BoxDecoration(color: bg),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Icon(
            Icons.location_on_outlined,
            color: Colors.white.withValues(alpha: 0.95),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'edit Location',
              style: AppFonts.mediumBold(
                18,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowField({
    required bool isDark,
    required String label,
    required Widget child,
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppFonts.medium(14, color: labelColor)),
          child,
        ],
      ),
    );
  }

  Widget _buildBottomButtons(bool isDark) {
    Widget buildBtn({required String iconPath, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: isDark ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Image.asset(iconPath, width: 28, height: 28),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          buildBtn(iconPath: 'assets/images/ic_cross.png', onTap: Get.back),
          buildBtn(
            iconPath: 'assets/images/ic_tick.png',
            onTap: _onTickPressed,
          ),
        ],
      ),
    );
  }

  void _onTickPressed() {
    final countryName =
        (_selectedCountry?.name ?? _memoryController.locationCountry.value)
            .trim();
    if (countryName.isEmpty) {
      Get.snackbar(
        'Country required',
        'Please select a country.',
        backgroundColor: Colors.red.withValues(alpha: 0.85),
        colorText: Colors.white,
      );
      return;
    }

    final state = _stateProvinceController.text.trim();
    final city = _cityTownController.text.trim();

    final combinedCity = () {
      if (city.isNotEmpty && state.isNotEmpty) return '$city, $state';
      if (city.isNotEmpty) return city;
      if (state.isNotEmpty) return state;
      return '';
    }();

    final flag = _selectedCountry != null
        ? _flagFromIso2(_selectedCountry!.code)
        : _memoryController.locationFlag.value;

    final payload = <String, dynamic>{
      'country': countryName,
      'city': combinedCity,
      'address': state,
      'flag': flag,
      'name': combinedCity.isNotEmpty ? '$combinedCity, $countryName' : countryName,
    };

    Get.back(result: payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        final isDark = _uiController.darkMode.value;
        final bg = isDark ? Colors.black : Colors.white;
        final valueColor = isDark ? Colors.white : Colors.black;

        Widget plainValueField(TextEditingController c) {
          return TextField(
            controller: c,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: AppFonts.medium(16, color: valueColor),
          );
        }

        return Container(
          color: bg,
          child: Column(
            children: [
              _buildHeader(isDark),
              Expanded(
                child: _isLoadingCountries
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: [
                            _buildRowField(
                              isDark: isDark,
                              label: 'Country',
                              child: Row(
                                children: [
                                  if (_selectedCountry != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        _flagFromIso2(_selectedCountry!.code),
                                        style: AppFonts.medium(16, color: valueColor),
                                      ),
                                    ),
                                  Expanded(
                                    child: TextField(
                                      controller: _countrySearchController,
                                      onTap: () =>
                                          setState(() => _showCountryDropdown = true),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      style: AppFonts.medium(16, color: valueColor),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_showCountryDropdown)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(horizontal: 10),
                                constraints: const BoxConstraints(maxHeight: 240),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[900] : Colors.white,
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : Colors.black12,
                                  ),
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: _filteredCountries.length,
                                  itemBuilder: (context, index) {
                                    final country = _filteredCountries[index];
                                    final flag = _flagFromIso2(country.code);
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        '$flag ${country.name}',
                                        style: AppFonts.medium(
                                          16,
                                          color: isDark ? Colors.white : Colors.black,
                                        ),
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedCountry = country;
                                          _countrySearchController.text = country.name;
                                          _showCountryDropdown = false;
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            _buildRowField(
                              isDark: isDark,
                              label: 'State/Province/Region',
                              child: plainValueField(_stateProvinceController),
                            ),
                            _buildRowField(
                              isDark: isDark,
                              label: 'City/Town',
                              child: plainValueField(_cityTownController),
                            ),
                            const SizedBox(height: 20),
                            _buildBottomButtons(isDark),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

