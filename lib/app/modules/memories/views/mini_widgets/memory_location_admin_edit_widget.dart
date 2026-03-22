import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:spacetime/services/world_locations_service.dart';
import 'package:spacetime/app/modules/memories/utils/memory_location_line_format.dart';
import 'package:spacetime/app/shared/widgets/tick_cross_action_button.dart';

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
  final GlobalKey _countryRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // Admin area [locationCity]: first segment → city/town, after first comma → state/province.
    final rawAdmin = _memoryController.locationCity.value.trim();
    final legacyAddr = _memoryController.locationAddress.value.trim();
    if (rawAdmin.isEmpty) {
      _cityTownController.text = '';
      _stateProvinceController.text = legacyAddr;
    } else {
      final p = MemoryLocationLineFormat.parseAdminArea(rawAdmin);
      _cityTownController.text = p.cityTown;
      _stateProvinceController.text =
          p.state.isNotEmpty ? p.state : legacyAddr;
    }
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

  void _closeCountryDropdown() {
    if (!_showCountryDropdown) return;
    setState(() => _showCountryDropdown = false);
  }

  String _formatCoord(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(6);
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
    return const SizedBox.shrink();
  }

  Widget _buildLeadingBackButton() {
    return GestureDetector(
      onTap: () => Get.back(),
      child: Container(
        margin: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
        padding: const EdgeInsets.all(6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage(AppImages.rectangle),
            fit: BoxFit.cover,
            colorFilter: _uiController.rectangleColorFilter,
          ),
        ),
        child: Image.asset(
          AppImages.arrowBack,
          fit: BoxFit.contain,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildRowField({
    required bool isDark,
    required String label,
    required Widget child,
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = isDark ? Colors.white54 : Colors.black12;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border.all(color: borderColor, width: 1),
        // elevation: 1,
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

  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TickCrossActionButton(
            iconPath: 'assets/images/ic_cross.png',
            onTap: Get.back,
          ),
          TickCrossActionButton(
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
      backgroundColor:
          _uiController.darkMode.value
              ? Colors.black
              : _uiController.getLightModeBackgroundColor(
                _uiController.mainColor.value,
              ),
      appBar: const CustomAppBar(
        
        title: 'edit Location',
        icon: Image(
          image: AssetImage('assets/images/location_1.png'),
          width: 22,
          height: 22,
          fit: BoxFit.contain,
        ),
      ),
      body: Obx(() {
        final isDark = _uiController.darkMode.value;
        // final bg = isDark ? Colors.grey[850] : Colors.white;
        final valueColor = isDark ? Colors.white : Colors.black;
        
        final bg = _uiController.darkMode.value
            ? Colors.white.withOpacity(0.06)
            : _uiController.getLightModeBackgroundColor(
              _uiController.mainColor.value,
            );

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

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeCountryDropdown,
          child: Stack(
            children: [
              Container(
                color: bg,
                child: Column(
                  children: [
                    Expanded(
                      child: _isLoadingCountries
                          ? const Center(child: CircularProgressIndicator())
                          : SingleChildScrollView(
                              padding: const EdgeInsets.only(top: 10),
                              child: Column(
                                children: [
                                  Container(
                                    child: Column(
                                      children: [
                                        _buildRowField(
                                          isDark: isDark,
                                          label: 'Country',
                                          child: Row(
                                            key: _countryRowKey,
                                            children: [
                                              if (_selectedCountry != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    right: 8,
                                                  ),
                                                  child: Text(
                                                    _flagFromIso2(
                                                      _selectedCountry!.code,
                                                    ),
                                                    style: AppFonts.medium(
                                                      16,
                                                      color: valueColor,
                                                    ),
                                                  ),
                                                ),
                                              Expanded(
                                                child: TextField(
                                                  controller: _countrySearchController,
                                                  onTap: () => setState(
                                                    () => _showCountryDropdown = true,
                                                  ),
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                  style: AppFonts.medium(
                                                    16,
                                                    color: valueColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildRowField(
                                          isDark: isDark,
                                          label: 'City/Town',
                                          child: plainValueField(
                                            _cityTownController,
                                          ),
                                        ),
                                        _buildRowField(
                                          isDark: isDark,
                                          label: 'State/Province/Region',
                                          child: plainValueField(
                                            _stateProvinceController,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _buildBottomButtons(),
                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              if (_showCountryDropdown)
                Positioned(
                  left: 10,
                  right: 10,
                  top: 58,
                  child: Material(
                    elevation: 10,
                    color: isDark ? Colors.grey[900] : Colors.white,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
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
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

