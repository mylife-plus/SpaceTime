#!/usr/bin/env python3
"""
Script to convert MemoryLocationPickerWidget from StatefulWidget to GetView
"""

import re

# Read the file
with open('lib/app/modules/memories/views/mini_widgets/memory_location_picker_widget.dart', 'r') as f:
    content = f.read()

# List of state variables and methods that need controller. prefix
state_vars = [
    'state', 'errorMessage', 'hasLocationPermission', 'isOfflineMode',
    'currentPosition', 'isSearching', 'searchResults', 'mapController',
    'annotationManager', 'selectedLocationMarker', 'memoryController',
    'uiController', 'searchController', 'searchFocusNode', 'showSearchResults',
    'serverUrl', 'serverErrorMessage', 'isInitializingServer'
]

# Methods that need controller. prefix
methods = [
    'initializeLocationPicker', 'initializeLocalTileServer', 'checkLocationPermission',
    'getCurrentLocation', 'addLocalTileSource', 'onSearchFocusChanged', 'onSearchChanged',
    'onMapCreated', 'onMapTap', 'moveToCurrentLocation', 'moveToLocation',
    'selectLocation', 'clearExistingMarkers', 'createRedMarkerImage',
    'createRedMarkerImageBytes', 'getLocationDetails', 'performLocationSearch',
    'selectSearchResult', 'onDonePressed'
]

# Replace state variable references with controller.
for var in state_vars:
    # Match patterns like: state.value, _searchController, etc.
    # Handle both with and without underscore prefix
    patterns = [
        (f'\\b{var}\\.', f'controller.{var}.'),
        (f'\\b_{var}\\.', f'controller.{var}.'),
        (f'\\b{var}\\b(?!\\.)', f'controller.{var}'),
        (f'\\b_{var}\\b(?!\\.)', f'controller.{var}'),
    ]
    for pattern, replacement in patterns:
        content = re.sub(pattern, replacement, content)

# Replace method calls with controller.
for method in methods:
    patterns = [
        (f'\\b{method}\\(', f'controller.{method}('),
        (f'\\b_{method}\\(', f'controller.{method}('),
    ]
    for pattern, replacement in patterns:
        content = re.sub(pattern, replacement, content)

# Write the updated content
with open('lib/app/modules/memories/views/mini_widgets/memory_location_picker_widget.dart', 'w') as f:
    f.write(content)

print("Conversion complete!")

