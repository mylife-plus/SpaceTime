# 🗺️ Mapbox Circle Layer Clustering Example

## ✅ **Setup Complete!**

The `CircleLayerClusteringPage` is now fully connected to your project's Mapbox API key and ready to use.

---

## 📋 **How It Works**

### **1. Mapbox API Key Configuration**

The clustering example automatically uses your project's Mapbox API key from the `.env` file:

**File: `.env`**
```
MAPBOX_ACCESS_TOKEN=pk.eyJ1IjoibW9vc2lhc2QiLCJhIjoiY21jZTV6MzFzMG9wMjJqcXdmY3VjZWV1biJ9.3FMDFTkqzcRTEVBIxyuXeA
```

**File: `lib/main.dart`** (lines 101-102)
```dart
await dotenv.load(fileName: ".env");
MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));
```

✅ **The API key is set globally**, so `CircleLayerClusteringPage` doesn't need to configure it again.

---

## 🚀 **How to Access the Clustering Example**

### **Option 1: Navigate Using Route**

```dart
import 'package:get/get.dart';
import 'package:spacetime/app/routes/app_pages.dart';

// Navigate to clustering example
Get.toNamed(Routes.CLUSTERING_EXAMPLE);
```

### **Option 2: Navigate Directly**

```dart
import 'package:get/get.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/map_view_widget_new.dart';

// Navigate to clustering example
Get.to(() => const CircleLayerClusteringPage());
```

---

## 📦 **Requirements**

### **1. Add GeoJSON Data File**

The clustering example requires a GeoJSON file with earthquake data.

**Create:** `assets/earthquakes.geojson`

**Sample GeoJSON structure:**
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "mag": 5.2,
        "place": "San Francisco Bay Area"
      },
      "geometry": {
        "type": "Point",
        "coordinates": [-122.4194, 37.7749]
      }
    }
  ]
}
```

### **2. Update pubspec.yaml**

Add the GeoJSON file to your assets:

```yaml
flutter:
  assets:
    - assets/earthquakes.geojson
```

---

## 🎨 **What the Example Demonstrates**

1. **Clustered GeoJSON Source** - Groups nearby points into clusters
2. **Circle Layers** - Visual representation of clusters and individual points
3. **Symbol Layers** - Shows count of points in each cluster
4. **Dynamic Styling** - Different colors/sizes based on cluster size

---

## 🔧 **Customization**

### **Change Cluster Radius**

Edit `lib/app/modules/map/views/mini_widgets/map_view_widget_new.dart`:

```dart
await style.addSource(
  mapbox.GeoJsonSource(
    id: _sourceId,
    data: geojsonString,
    cluster: true,
    clusterRadius: 50,  // Change this value (default: 50)
    clusterMaxZoom: 14, // Max zoom level for clustering
  ),
);
```

### **Change Cluster Colors**

```dart
await style.addLayer(
  mapbox.CircleLayer(
    id: _clusterLayerId,
    sourceId: _sourceId,
    filter: ['has', 'point_count'],
    circleColor: 0xFF51BBD6,  // Change color (hex format: 0xFFRRGGBB)
    circleRadius: 20.0,        // Change size
  ),
);
```

---

## 📍 **Example: Add Button to Settings**

Add a button in your settings page to open the clustering example:

```dart
ListTile(
  leading: Icon(Icons.scatter_plot),
  title: Text('Clustering Example'),
  subtitle: Text('View Mapbox circle layer clustering demo'),
  onTap: () {
    Get.toNamed(Routes.CLUSTERING_EXAMPLE);
  },
)
```

---

## ✨ **Summary**

✅ **Mapbox API key** - Automatically loaded from `.env` file  
✅ **Route configured** - Access via `Routes.CLUSTERING_EXAMPLE`  
✅ **No additional setup** - Just add GeoJSON file and update pubspec.yaml  
✅ **Fully documented** - Code includes detailed comments  

---

## 🧪 **Testing**

1. Add `assets/earthquakes.geojson` file
2. Update `pubspec.yaml` to include the asset
3. Run the app
4. Navigate to clustering example:
   ```dart
   Get.toNamed(Routes.CLUSTERING_EXAMPLE);
   ```
5. You should see a map with clustered earthquake data

---

## 📚 **Learn More**

- [Mapbox Clustering Documentation](https://docs.mapbox.com/mapbox-gl-js/example/cluster/)
- [GeoJSON Format](https://geojson.org/)
- [Mapbox Styles](https://docs.mapbox.com/api/maps/styles/)

