import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final FocusNode _countryFocusNode = FocusNode();
  final FocusNode _cityFocusNode = FocusNode();
  final FocusNode _stateFocusNode = FocusNode();

  bool _isLoadingCountries = true;
  bool _showCountryDropdown = false;
  List<Country> _filteredCountries = <Country>[];
  Country? _selectedCountry;
  bool _didSubmit = false;
  late final String _originalCountry;
  late final String _originalCity;
  late final String _originalAddress;
  late final String _originalFlag;
  late final String _originalName;
  final GlobalKey _countryRowKey = GlobalKey();
  final LayerLink _countryFieldLayerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _originalCountry = _memoryController.locationCountry.value;
    _originalCity = _memoryController.locationCity.value;
    _originalAddress = _memoryController.locationAddress.value;
    _originalFlag = _memoryController.locationFlag.value;
    _originalName = _memoryController.locationName.value;

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
    _dedupeCityStateIfIdentical();
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
    _countryFocusNode.dispose();
    _cityFocusNode.dispose();
    _stateFocusNode.dispose();
    super.dispose();
  }

  void _restoreOriginalLocationTextIfCancelled() {
    _memoryController.setEnhancedLocationData(<String, dynamic>{
      'latitude': _memoryController.locationLatitude.value,
      'longitude': _memoryController.locationLongitude.value,
      'country': _originalCountry,
      'city': _originalCity,
      'address': _originalAddress,
      'flag': _originalFlag,
      'name': _originalName,
    });
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

  void _onCountryOverlayTap() {
    _closeCountryDropdown();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// If city/town equals state/province/region, clear the latter (duplicate admin).
  void _dedupeCityStateIfIdentical() {
    final city = _cityTownController.text.trim();
    final state = _stateProvinceController.text.trim();
    if (city.isNotEmpty &&
        state.isNotEmpty &&
        city.toLowerCase() == state.toLowerCase()) {
      _stateProvinceController.clear();
    }
  }

  String _formatCoord(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(6);
  }

  String _gpsLocationDisplayText() {
    final lat = _memoryController.locationLatitude.value;
    final lng = _memoryController.locationLongitude.value;
    if (lat == null || lng == null) return '—';
    return '${_formatCoord(lat)}, ${_formatCoord(lng)}';
  }

  void _copyGpsLocation() {
    final lat = _memoryController.locationLatitude.value;
    final lng = _memoryController.locationLongitude.value;
    if (lat == null || lng == null) return;
    final text = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    Clipboard.setData(ClipboardData(text: text));
    final isDark = _uiController.darkMode.value;
    final bg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final fg = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final sub = isDark ? Colors.white70 : const Color(0xFF636366);
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 14,
      isDismissible: true,
      backgroundColor: bg,
      boxShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      maxWidth: 420,
      titleText: Text(
        'Copied',
        textAlign: TextAlign.left,
        style: AppFonts.bold(17, color: fg),
      ),
      messageText: Text(
        'GPS coordinates are on the clipboard.',
        textAlign: TextAlign.left,
        style: AppFonts.medium(14, color: sub).copyWith(height: 1.35),
      ),
    );
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

  Widget _buildGpsLocationRowField({
    required bool isDark,
    required Color valueColor,
  }) {
    final labelColor = (isDark ? Colors.white70 : Colors.grey[600]!)
        .withValues(alpha: 0.72);
    final mutedValue = valueColor.withValues(alpha: 0.72);
    final borderColor =
        isDark ? Colors.white30 : Colors.grey.shade400.withValues(alpha: 0.55);
    final baseFill = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFE8E8E8);
    final canCopy = _memoryController.locationLatitude.value != null &&
        _memoryController.locationLongitude.value != null;

    return InkWell(
      onTap: canCopy ? _copyGpsLocation : null,
      child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: baseFill,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.black.withValues(alpha: isDark ? 0.22 : 0.07),
                      Colors.transparent,
                      Colors.white.withValues(alpha: isDark ? 0.04 : 0.35),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    ),
                    left: BorderSide(
                      color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GPS Location',
                        style: AppFonts.medium(14, color: labelColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _gpsLocationDisplayText(),
                        style: AppFonts.medium(16, color: mutedValue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildRowField({
    required bool isDark,
    required String label,
    required Widget child,
    FocusNode? focusNode,
    VoidCallback? onRowTap,
  }) {
    final labelColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final borderColor = isDark ? Colors.white54 : Colors.black12;
    void handleRowTap() {
      _closeCountryDropdown();
      if (onRowTap != null) {
        onRowTap();
      } else {
        focusNode?.requestFocus();
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: handleRowTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
            onTap: () {
              _didSubmit = false;
              _restoreOriginalLocationTextIfCancelled();
              Get.back();
            },
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

    var state = _stateProvinceController.text.trim();
    final city = _cityTownController.text.trim();
    if (city.isNotEmpty &&
        state.isNotEmpty &&
        city.toLowerCase() == state.toLowerCase()) {
      state = '';
    }

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

    _didSubmit = true;
    Get.back(result: payload);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_didSubmit) {
          _restoreOriginalLocationTextIfCancelled();
        }
      },
      child: Scaffold(
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

        Widget plainValueField(
          TextEditingController c, {
          FocusNode? focusNode,
          TextInputAction? textInputAction,
        }) {
          return TextField(
            controller: c,
            focusNode: focusNode,
            textInputAction: textInputAction,
            onTap: _closeCountryDropdown,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
            style: AppFonts.medium(16, color: valueColor),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final dropdownWidth =
                (constraints.maxWidth - 20).clamp(0.0, double.infinity);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  color: bg,
                  child: Column(
                    children: [
                      Expanded(
                        child:
                            _isLoadingCountries
                                ? const Center(child: CircularProgressIndicator())
                                : GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () =>
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus(),
                                  child: SingleChildScrollView(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight - 10,
                                    ),
                                    child: Column(
                                    children: [
                                      Column(
                                        children: [
                                          _buildGpsLocationRowField(
                                            isDark: isDark,
                                            valueColor: valueColor,
                                          ),
                                          CompositedTransformTarget(
                                            link: _countryFieldLayerLink,
                                            child: _buildRowField(
                                              isDark: isDark,
                                              label: 'Country',
                                              onRowTap: () {
                                                _countryFocusNode.requestFocus();
                                                setState(() {
                                                  _showCountryDropdown = true;
                                                });
                                              },
                                              child: Row(
                                                key: _countryRowKey,
                                                children: [
                                                  if (_selectedCountry != null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
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
                                                      controller:
                                                          _countrySearchController,
                                                      focusNode:
                                                          _countryFocusNode,
                                                      onTap: () {
                                                        _countryFocusNode
                                                            .requestFocus();
                                                        setState(() {
                                                          _showCountryDropdown =
                                                              true;
                                                        });
                                                      },
                                                      onTapOutside: (_) =>
                                                          FocusManager
                                                              .instance
                                                              .primaryFocus
                                                              ?.unfocus(),
                                                      decoration:
                                                          const InputDecoration(
                                                            isDense: true,
                                                            border:
                                                                InputBorder.none,
                                                            contentPadding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              vertical: 4,
                                                            ),
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
                                          ),
                                          _buildRowField(
                                            isDark: isDark,
                                            label: 'City/Town',
                                            focusNode: _cityFocusNode,
                                            child: plainValueField(
                                              _cityTownController,
                                              focusNode: _cityFocusNode,
                                              textInputAction:
                                                  TextInputAction.next,
                                            ),
                                          ),
                                          _buildRowField(
                                            isDark: isDark,
                                            label: 'State/Province/Region',
                                            focusNode: _stateFocusNode,
                                            child: plainValueField(
                                              _stateProvinceController,
                                              focusNode: _stateFocusNode,
                                              textInputAction:
                                                  TextInputAction.done,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _buildBottomButtons(),
                                      const SizedBox(height: 40),
                                    ],
                                  ),
                                ),
                                  ),
                                ),
                      ),
                    ],
                  ),
                ),
                if (_showCountryDropdown)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onCountryOverlayTap,
                      child: const SizedBox.expand(),
                    ),
                  ),
                if (_showCountryDropdown)
                  CompositedTransformFollower(
                    link: _countryFieldLayerLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomLeft,
                    followerAnchor: Alignment.topLeft,
                    offset: const Offset(10, 2),
                    child: SizedBox(
                      width: dropdownWidth,
                      child: Material(
                        elevation: 10,
                        color: isDark ? Colors.grey[900] : Colors.white,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  ),
              ],
            );
          },
        );
      }),
    ));
  }
}

