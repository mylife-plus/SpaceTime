# 📍 Individual Point Labels Guide

## ✅ **What Was Added**

Individual memory points now have **text labels** displayed below the icon.

---

## 🏗️ **Implementation**

### **Layer Structure:**

1. **Icon Layer** (`UNCLUSTERED_LAYER_ID`)
   - Shows custom circular icon
   - Blue color, smaller than clusters

2. **Label Layer** (`INDIVIDUAL_COUNT_LAYER_ID`)
   - Shows text below the icon
   - Black text with white halo
   - Positioned below icon using `textOffset`

---

## 🎨 **Current Configuration**

```dart
mapbox.SymbolLayer(
  id: INDIVIDUAL_COUNT_LAYER_ID,
  sourceId: MEMORY_SOURCE_ID,
  filter: ['!', ['has', 'point_count']],
  textField: '{description}',        // Shows memory description
  textSize: 11.0,
  textColor: 0xFF000000,             // Black text
  textHaloColor: 0xFFFFFFFF,         // White halo
  textHaloWidth: 2.0,
  textHaloBlur: 1.0,
  textOffset: [0.0, 2.0],            // Below icon
  textAnchor: mapbox.TextAnchor.TOP, // Anchor at top
  textAllowOverlap: false,           // Don't overlap
  textMaxWidth: 10.0,                // Wrap after 10 chars
)
```

---

## 📊 **Available GeoJSON Properties**

You can use any of these properties in `textField`:

| Property | Example | Use Case |
|----------|---------|----------|
| `{description}` | "Trip to Paris" | Memory description (current) |
| `{location_name}` | "Eiffel Tower" | Location name |
| `{location_city}` | "Paris" | City name |
| `{location_country}` | "France" | Country name |
| `{year}` | "2024" | Year only |
| `{memory_date}` | "2024-01-15" | Full date |
| `{category}` | "travel" | Memory category |

---

## 🔧 **Customization Options**

### **Option 1: Show Location Name Instead**

```dart
textField: '{location_name}',
```

### **Option 2: Show City + Year**

Unfortunately, the Flutter SDK doesn't support string concatenation in `textField`. You need to choose one property.

**Workaround:** Add a combined property in GeoJSON generation:

In `memory_geojson_service.dart`:
```dart
'properties': {
  // ... existing properties
  'label': '${memory['location_city']} - $year', // Combined label
}
```

Then use:
```dart
textField: '{label}',
```

### **Option 3: Show Only Year**

```dart
textField: '{year}',
```

### **Option 4: Show First Few Characters of Description**

The `textMaxWidth` property already limits the width, but you can make it shorter:

```dart
textMaxWidth: 5.0, // Shorter labels
```

### **Option 5: Hide Labels at Lower Zoom Levels**

Add zoom-based visibility using `setStyleLayerProperty`:

```dart
await mapboxMap!.style.setStyleLayerProperty(
  INDIVIDUAL_COUNT_LAYER_ID,
  'text-opacity',
  [
    'interpolate',
    ['linear'],
    ['zoom'],
    14, 0.0,  // Hidden below zoom 14
    15, 1.0,  // Fully visible at zoom 15+
  ],
);
```

---

## 🎯 **Recommended Settings**

### **For Short Labels (Location Names):**

```dart
textField: '{location_name}',
textSize: 11.0,
textMaxWidth: 15.0,
textAllowOverlap: false,
```

### **For Minimal Labels (Year Only):**

```dart
textField: '{year}',
textSize: 10.0,
textMaxWidth: 5.0,
textAllowOverlap: true, // Can overlap since they're small
```

### **For No Labels (Icon Only):**

Simply don't add the `INDIVIDUAL_COUNT_LAYER_ID` layer, or set:

```dart
textField: '', // Empty string
```

---

## 🐛 **Troubleshooting**

### **Labels Not Showing:**

1. **Check if property exists:**
   - Verify the GeoJSON has the property you're using
   - Check console for errors

2. **Check zoom level:**
   - Labels might be hidden at current zoom
   - Try zooming in

3. **Check overlap settings:**
   - If `textAllowOverlap: false`, labels might be hidden to avoid clutter
   - Try setting to `true`

4. **Check text color:**
   - Black text on dark background won't show
   - Increase `textHaloWidth` for better visibility

### **Labels Too Long:**

1. **Reduce `textMaxWidth`:**
   ```dart
   textMaxWidth: 8.0, // Shorter
   ```

2. **Use shorter property:**
   ```dart
   textField: '{location_city}', // Instead of description
   ```

3. **Add truncated property in GeoJSON:**
   ```dart
   'label_short': description.substring(0, min(20, description.length)),
   ```

### **Labels Overlapping:**

1. **Disable overlap:**
   ```dart
   textAllowOverlap: false,
   ```

2. **Increase spacing:**
   ```dart
   textPadding: 5.0, // Add padding around text
   ```

3. **Show only at high zoom:**
   - Use zoom-based opacity (see Option 5 above)

---

## 📝 **Current Setup Summary**

✅ **Icon:** Custom blue circle (60px)  
✅ **Label:** Memory description  
✅ **Position:** Below icon  
✅ **Style:** Black text, white halo  
✅ **Overlap:** Disabled (prevents clutter)  

---

## 🚀 **Next Steps**

1. **Test the labels:**
   - Run the app
   - Zoom in to see individual points
   - Check if labels appear below icons

2. **Adjust if needed:**
   - Change `textField` to show different property
   - Adjust `textSize` for readability
   - Modify `textOffset` to change position

3. **Consider adding:**
   - Zoom-based visibility
   - Combined label property in GeoJSON
   - Different labels for different categories

