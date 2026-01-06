# 🎨 Clustering Styling Quick Reference

## 📊 **Property Comparison**

### **Cluster Circles**

| Property | Current (MapControllerNew) | Target (CircleLayerClusteringPage) | Change |
|----------|---------------------------|-----------------------------------|--------|
| `circleColor` | `0xFF4CAF50` (Green) | `0xFF51BBD6` (Blue) | ✅ Update |
| `circleRadius` | `25.0` | `20.0` | ✅ Update |
| `circleOpacity` | `1.0` | `0.9` | ✅ Update |
| `circleBlur` | ❌ Not set | `0.2` | ⭐ **ADD** |
| `circleStrokeWidth` | `3` | `3.0` | ✅ Same |
| `circleStrokeColor` | `0xFFFFFFFF` | `0xFFFFFFFF` | ✅ Same |

---

### **Cluster Count Text**

| Property | Current | Target | Change |
|----------|---------|--------|--------|
| `textField` | `'{point_count}'` | `'{point_count_abbreviated}'` | ✅ Update |
| `textSize` | `12.0` | `14.0` | ✅ Update |
| `textHaloBlur` | ❌ Not set | `0.5` | ⭐ **ADD** |
| `textIgnorePlacement` | ❌ Not set | `true` | ⭐ **ADD** |
| `textAllowOverlap` | `true` | `true` | ✅ Same |
| `textColor` | `0xFFFFFFFF` | `0xFFFFFFFF` | ✅ Same |
| `textHaloColor` | `0xFF000000` | `0xFF000000` | ✅ Same |
| `textHaloWidth` | `1.5` | `1.5` | ✅ Same |

---

### **Individual Memory Circles**

| Property | Current | Target | Change |
|----------|---------|--------|--------|
| `circleColor` | `0xFF2196F3` (Blue) | `0xFF11B4DA` (Light Blue) | ✅ Update |
| `circleRadius` | `20.0` | `8.0` | ⭐ **REDUCE** |
| `circleOpacity` | `0.9` | `0.95` | ✅ Update |
| `circleBlur` | ❌ Not set | `0.1` | ⭐ **ADD** |
| `circleStrokeWidth` | `2` | `2.0` | ✅ Same |
| `circleStrokeColor` | `0xFFFFFFFF` | `0xFFFFFFFF` | ✅ Same |

---

### **Individual Count Text**

| Property | Current | Target | Change |
|----------|---------|--------|--------|
| `textField` | `'1'` | `'1'` | ✅ Same |
| `textSize` | `10.0` | `10.0` | ✅ Same |
| `textHaloBlur` | ❌ Not set | `0.3` | ⭐ **ADD** |
| `textIgnorePlacement` | ❌ Not set | `true` | ⭐ **ADD** |
| `textFont` | `['Open Sans Bold', ...]` | ❌ Not set | ✅ Remove |
| `textAllowOverlap` | `true` | `true` | ✅ Same |
| `textColor` | `0xFFFFFFFF` | `0xFFFFFFFF` | ✅ Same |
| `textHaloColor` | `0xFF000000` | `0xFF000000` | ✅ Same |
| `textHaloWidth` | `1.0` | `1.0` | ✅ Same |

---

### **GeoJSON Source**

| Property | Current | Target | Change |
|----------|---------|--------|--------|
| `cluster` | `true` | `true` | ✅ Same |
| `clusterRadius` | `50` | `50` | ✅ Same |
| `clusterMaxZoom` | `MapboxZoomHelper().clusterMaxZoom.value` | `14` | ✅ Hardcode |
| `clusterMinPoints` | `2` | `2` | ✅ Same |
| `clusterProperties` | ❌ Not set | `{}` | ⭐ **ADD** |

---

### **Animation Durations**

| Action | Current | Target | Change |
|--------|---------|--------|--------|
| Zoom In/Out | Variable | `500ms` | ✅ Standardize |
| Cluster Tap Zoom | Variable | `800ms` | ✅ Standardize |
| Reset/Major Move | Variable | `1500ms` | ✅ Standardize |

---

## 🎯 **Key Differences Summary**

### **Visual Enhancements:**
1. ⭐ **Blur Effects** - Adds `circleBlur` and `textHaloBlur` for smoother appearance
2. ⭐ **Smaller Individuals** - Reduces individual point radius from 20 to 8
3. ⭐ **Abbreviated Counts** - Shows "10K" instead of "10000"
4. ⭐ **Text Placement** - Adds `textIgnorePlacement` for smooth transitions

### **Performance Enhancements:**
1. ⭐ **Hardcoded Zoom** - Removes dependency on MapboxZoomHelper for clustering
2. ⭐ **Cluster Properties** - Enables future custom properties
3. ⭐ **Consistent Animations** - Standardized timing for professional feel

---

## 🔧 **Copy-Paste Ready Code Snippets**

### **Cluster Circle Layer:**
```dart
await mapboxMap!.style.addLayer(
  mapbox.CircleLayer(
    id: CLUSTER_LAYER_ID,
    sourceId: MEMORY_SOURCE_ID,
    filter: ['has', 'point_count'],
    circleColor: 0xFF51BBD6,
    circleRadius: 20.0,
    circleStrokeWidth: 3.0,
    circleStrokeColor: 0xFFFFFFFF,
    circleOpacity: 0.9,
    circleBlur: 0.2,  // ⭐ NEW
  ),
);
```

### **Cluster Count Text Layer:**
```dart
await mapboxMap!.style.addLayer(
  mapbox.SymbolLayer(
    id: CLUSTER_COUNT_LAYER_ID,
    sourceId: MEMORY_SOURCE_ID,
    filter: ['has', 'point_count'],
    textField: '{point_count_abbreviated}',  // ⭐ CHANGED
    textSize: 14.0,  // ⭐ CHANGED
    textColor: 0xFFFFFFFF,
    textHaloColor: 0xFF000000,
    textHaloWidth: 1.5,
    textHaloBlur: 0.5,  // ⭐ NEW
    textAllowOverlap: true,
    textIgnorePlacement: true,  // ⭐ NEW
  ),
);
```

### **Individual Circle Layer:**
```dart
await mapboxMap!.style.addLayer(
  mapbox.CircleLayer(
    id: UNCLUSTERED_LAYER_ID,
    sourceId: MEMORY_SOURCE_ID,
    filter: ['!', ['has', 'point_count']],
    circleColor: 0xFF11B4DA,  // ⭐ CHANGED
    circleRadius: 8.0,  // ⭐ CHANGED
    circleStrokeWidth: 2.0,
    circleStrokeColor: 0xFFFFFFFF,
    circleOpacity: 0.95,
    circleBlur: 0.1,  // ⭐ NEW
  ),
);
```

### **Individual Count Text Layer:**
```dart
await mapboxMap!.style.addLayer(
  mapbox.SymbolLayer(
    id: INDIVIDUAL_COUNT_LAYER_ID,
    sourceId: MEMORY_SOURCE_ID,
    filter: ['!', ['has', 'point_count']],
    textField: '1',
    textSize: 10.0,
    textColor: 0xFFFFFFFF,
    textHaloColor: 0xFF000000,
    textHaloWidth: 1.0,
    textHaloBlur: 0.3,  // ⭐ NEW
    textAllowOverlap: true,
    textIgnorePlacement: true,  // ⭐ NEW
  ),
);
```

---

## ✅ **Checklist**

- [ ] Update cluster circle: color, radius, opacity, **add blur**
- [ ] Update cluster text: **abbreviated**, size, **add halo blur**, **add ignore placement**
- [ ] Update individual circle: color, **reduce radius**, **add blur**
- [ ] Update individual text: **add halo blur**, **add ignore placement**, **remove font**
- [ ] Update GeoJSON source: **hardcode clusterMaxZoom**, **add clusterProperties**
- [ ] Standardize animations: **500ms zoom**, **800ms cluster**, **1500ms reset**


