// import 'dart:convert';
// import 'dart:math';
// import 'dart:typed_data';
// import 'dart:ui';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
// import 'package:spacetime/app/modules/map/controllers/map_controller.dart';
// import 'package:spacetime/services/connectivity_service.dart';
// import '../../../../../services/memory_clustering_service.dart';
// import '../../../ui/controllers/ui_controller.dart';
// import '../../../map/views/mini_widgets/click_listener.dart';
// import 'memory_cluster_popup.dart';

// enum ClusterLevel {
//   initial,
//   subgroup,
// }

// class MemoryGlobeWidget extends StatefulWidget {
//   final List<Map<String, dynamic>> memories;
//   final Function(Map<String, dynamic>)? onMemorySelected;
//   final Function(List<Map<String, dynamic>>)? onClusterSelected;

//   const MemoryGlobeWidget({
//     super.key,
//     required this.memories,
//     this.onMemorySelected,
//     this.onClusterSelected,
//   });

//   @override
//   State<MemoryGlobeWidget> createState() => _MemoryGlobeWidgetState();
// }

// class _MemoryGlobeWidgetState extends State<MemoryGlobeWidget> {
//   mapbox.MapboxMap? mapController;
//   mapbox.PointAnnotationManager? annotationManager;
//   mapbox.PolylineAnnotationManager? lineAnnotationManager;

//   final uiController = Get.find<UiController>();

//   List<MemoryCluster> currentClusters = [];
//   List<ChronologicalArrow> currentArrows = [];
//   ClusterLevel currentLevel = ClusterLevel.initial;
//   MemoryCluster? selectedCluster;

//   bool isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _initializeClusters();
//   }

//   void _initializeClusters() {
//     try {
//       // Convert memories to MemoryLocation objects
//       final memoryLocations = widget.memories
//           .where((memory) => _hasValidCoordinates(memory))
//           .map((memory) => MemoryLocation.fromMap(memory))
//           .toList();

//       if (memoryLocations.isEmpty) {
//         setState(() {
//           isLoading = false;
//         });
//         return;
//       }

//       // Initial clustering with 5km radius
//       currentClusters = MemoryClusteringService.clusterMemories(
//         memoryLocations,
//         MemoryClusteringService.initialClusterRadiusKm,
//       );

//       // Generate chronological arrows
//       currentArrows = MemoryClusteringService.generateChronologicalArrows(currentClusters);

//       setState(() {
//         isLoading = false;
//       });

//       debugPrint('Initialized ${currentClusters.length} clusters from ${memoryLocations.length} memories');
//     } catch (e) {
//       debugPrint('Error initializing clusters: $e');
//       setState(() {
//         isLoading = false;
//       });
//     }
//   }

//   bool _hasValidCoordinates(Map<String, dynamic> memory) {
//     final locationStr = memory['location'] as String? ?? '';
//     if (locationStr.contains(',')) {
//       final parts = locationStr.split(',');
//       if (parts.length >= 2) {
//         final lat = double.tryParse(parts[0].trim());
//         final lng = double.tryParse(parts[1].trim());
//         return lat != null && lng != null && lat != 0.0 && lng != 0.0;
//       }
//     }
//     return false;
//   }

//   Future<void> _onMapCreated(mapbox.MapboxMap controller) async {
//     mapController = controller;

//     // Create annotation managers
//     annotationManager = await controller.annotations.createPointAnnotationManager();
//     lineAnnotationManager = await controller.annotations.createPolylineAnnotationManager();

//     // Set up click listeners
//     annotationManager!.addOnPointAnnotationClickListener(
//       AnnotationClickListener((annotation) async {
//         await _onMarkerTapped(annotation);
//       }),
//     );

//     // Display initial clusters
//     await _displayClusters();

//     // Set initial camera position
//     if (currentClusters.isNotEmpty) {
//       await _setCameraToFitClusters();
//     }
//   }

//   Future<void> _displayClusters() async {
//     if (mapController == null || annotationManager == null) return;

//     try {
//       // Clear existing annotations
//       await annotationManager!.deleteAll();
//       await lineAnnotationManager!.deleteAll();

//       // Create cluster markers
//       final List<mapbox.PointAnnotationOptions> markerOptions = [];

//       for (int i = 0; i < currentClusters.length; i++) {
//         final cluster = currentClusters[i];

//         // Create marker image
//         final imageBytes = await _createClusterMarkerImage(cluster);
//         final imageName = 'cluster_marker_${cluster.id}';

//         await mapController!.style.addStyleImage(
//           imageName,
//           1.0,
//           mapbox.MbxImage(data: imageBytes, width: 60, height: 60),
//           false,
//           [],
//           [],
//           null,
//         );

//         markerOptions.add(
//           mapbox.PointAnnotationOptions(
//             geometry: mapbox.Point(
//               coordinates: mapbox.Position(
//                 cluster.centerLongitude,
//                 cluster.centerLatitude,
//               ),
//             ),
//             iconImage: imageName,
//             iconSize: cluster.isSingleMemory ? 0.6 : 0.8,
//           ),
//         );
//       }

//       // Create markers
//       await annotationManager!.createMulti(markerOptions);

//       // Display chronological arrows
//       await _displayArrows();

//     } catch (e) {
//       debugPrint('Error displaying clusters: $e');
//     }
//   }

//   Future<void> _displayArrows() async {
//     if (lineAnnotationManager == null || currentArrows.isEmpty) return;

//     try {
//       final List<mapbox.PolylineAnnotationOptions> lineOptions = [];

//       for (final arrow in currentArrows) {
//         // Create curved line between points
//         final points = _createCurvedLine(
//           arrow.fromLatitude, arrow.fromLongitude,
//           arrow.toLatitude, arrow.toLongitude,
//         );

//         lineOptions.add(
//           mapbox.PolylineAnnotationOptions(
//             geometry: mapbox.LineString(coordinates: points),
//             lineColor: uiController.darkMode.value ? 0xFF4CAF50 : 0xFF2196F3,
//             lineWidth: 2.0,
//             lineOpacity: 0.7,
//           ),
//         );

//         // Add arrow head
//         await _addArrowHead(arrow);
//       }

//       await lineAnnotationManager!.createMulti(lineOptions);

//     } catch (e) {
//       debugPrint('Error displaying arrows: $e');
//     }
//   }

//   List<mapbox.Position> _createCurvedLine(double lat1, double lng1, double lat2, double lng2) {
//     final points = <mapbox.Position>[];
//     const int segments = 20;

//     // Calculate control point for curve (offset perpendicular to line)
//     final distance = MemoryClusteringService.calculateDistance(lat1, lng1, lat2, lng2);
//     final offset = distance * 0.1; // 10% of distance for curve

//     // Create curved path
//     for (int i = 0; i <= segments; i++) {
//       final t = i / segments;
//       final lat = lat1 + (lat2 - lat1) * t + offset * sin(t * 3.14159);
//       final lng = lng1 + (lng2 - lng1) * t;
//       points.add(mapbox.Position(lng, lat));
//     }

//     return points;
//   }

//   Future<void> _addArrowHead(ChronologicalArrow arrow) async {
//     if (mapController == null) return;

//     try {
//       // Create arrow head image
//       final imageBytes = await _createArrowHeadImage();
//       final imageName = 'arrow_head_${arrow.fromClusterId}_${arrow.toClusterId}';

//       await mapController!.style.addStyleImage(
//         imageName,
//         1.0,
//         mapbox.MbxImage(data: imageBytes, width: 20, height: 20),
//         false,
//         [],
//         [],
//         null,
//       );

//       // Place arrow head at 80% of the way to target
//       final t = 0.8;
//       final arrowLat = arrow.fromLatitude + (arrow.toLatitude - arrow.fromLatitude) * t;
//       final arrowLng = arrow.fromLongitude + (arrow.toLongitude - arrow.fromLongitude) * t;

//       await annotationManager!.create(
//         mapbox.PointAnnotationOptions(
//           geometry: mapbox.Point(coordinates: mapbox.Position(arrowLng, arrowLat)),
//           iconImage: imageName,
//           iconSize: 0.5,
//           iconRotate: arrow.bearing,
//         ),
//       );

//     } catch (e) {
//       debugPrint('Error adding arrow head: $e');
//     }
//   }

//   Future<Uint8List> _createClusterMarkerImage(MemoryCluster cluster) async {
//     const double size = 60.0;
//     final recorder = PictureRecorder();
//     final canvas = Canvas(recorder);
//     final radius = size / 2;

//     // Choose color based on cluster type and memory count
//     Color markerColor;
//     if (cluster.isSingleMemory) {
//       markerColor = const Color(0xFF2196F3); // Blue for single memories
//     } else if (cluster.memoryCount <= 5) {
//       markerColor = const Color(0xFF4CAF50); // Green for small clusters
//     } else if (cluster.memoryCount <= 15) {
//       markerColor = const Color(0xFFFF9800); // Orange for medium clusters
//     } else {
//       markerColor = const Color(0xFFF44336); // Red for large clusters
//     }

//     // Draw circle
//     final paint = Paint()..color = markerColor;
//     canvas.drawCircle(Offset(radius, radius), radius - 3, paint);

//     // Add white border
//     final border = Paint()
//       ..color = Colors.white
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 3;
//     canvas.drawCircle(Offset(radius, radius), radius - 3, border);

//     // Draw count text
//     final textPainter = TextPainter(
//       text: TextSpan(
//         text: cluster.memoryCount.toString(),
//         style: const TextStyle(
//           color: Colors.white,
//           fontSize: 16,
//           fontWeight: FontWeight.bold,
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//       textAlign: TextAlign.center,
//     );

//     textPainter.layout();
//     textPainter.paint(
//       canvas,
//       Offset(
//         radius - textPainter.width / 2,
//         radius - textPainter.height / 2,
//       ),
//     );

//     final picture = recorder.endRecording();
//     final image = await picture.toImage(size.toInt(), size.toInt());
//     final byteData = await image.toByteData(format: ImageByteFormat.png);

//     return byteData!.buffer.asUint8List();
//   }

//   Future<Uint8List> _createArrowHeadImage() async {
//     const double size = 20.0;
//     final recorder = PictureRecorder();
//     final canvas = Canvas(recorder);

//     final paint = Paint()
//       ..color = uiController.darkMode.value ? const Color(0xFF4CAF50) : const Color(0xFF2196F3)
//       ..style = PaintingStyle.fill;

//     // Draw arrow head triangle
//     final path = Path();
//     path.moveTo(size * 0.8, size * 0.5); // Point
//     path.lineTo(size * 0.2, size * 0.2); // Top
//     path.lineTo(size * 0.2, size * 0.8); // Bottom
//     path.close();

//     canvas.drawPath(path, paint);

//     final picture = recorder.endRecording();
//     final image = await picture.toImage(size.toInt(), size.toInt());
//     final byteData = await image.toByteData(format: ImageByteFormat.png);

//     return byteData!.buffer.asUint8List();
//   }

//   Future<void> _setCameraToFitClusters() async {
//     if (mapController == null || currentClusters.isEmpty) return;

//     try {
//       // Calculate bounds of all clusters
//       double minLat = currentClusters.first.centerLatitude;
//       double maxLat = currentClusters.first.centerLatitude;
//       double minLng = currentClusters.first.centerLongitude;
//       double maxLng = currentClusters.first.centerLongitude;

//       for (final cluster in currentClusters) {
//         minLat = minLat < cluster.centerLatitude ? minLat : cluster.centerLatitude;
//         maxLat = maxLat > cluster.centerLatitude ? maxLat : cluster.centerLatitude;
//         minLng = minLng < cluster.centerLongitude ? minLng : cluster.centerLongitude;
//         maxLng = maxLng > cluster.centerLongitude ? maxLng : cluster.centerLongitude;
//       }

//       // Add padding
//       const double padding = 0.1;
//       minLat -= padding;
//       maxLat += padding;
//       minLng -= padding;
//       maxLng += padding;

//       // Set camera to fit bounds
//       await mapController!.flyTo(
//         mapbox.CameraOptions(
//           center: mapbox.Point(
//             coordinates: mapbox.Position(
//               (minLng + maxLng) / 2,
//               (minLat + maxLat) / 2,
//             ),
//           ),
//           zoom: _calculateZoomLevel(minLat, maxLat, minLng, maxLng),
//         ),
//         mapbox.MapAnimationOptions(duration: 1000),
//       );

//     } catch (e) {
//       debugPrint('Error setting camera: $e');
//     }
//   }

//   double _calculateZoomLevel(double minLat, double maxLat, double minLng, double maxLng) {
//     final double latDiff = maxLat - minLat;
//     final double lngDiff = maxLng - minLng;
//     final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

//     if (maxDiff > 10) return 2.0;
//     if (maxDiff > 5) return 4.0;
//     if (maxDiff > 1) return 6.0;
//     if (maxDiff > 0.1) return 8.0;
//     return 10.0;
//   }

//   Future<void> _onMarkerTapped(mapbox.PointAnnotation annotation) async {
//     try {
//       // Find which cluster was tapped
//       final tappedCluster = currentClusters.firstWhereOrNull(
//         (cluster) => annotation.geometry.coordinates.lng == cluster.centerLongitude &&
//                     annotation.geometry.coordinates.lat == cluster.centerLatitude,
//       );

//       if (tappedCluster == null) return;

//       if (currentLevel == ClusterLevel.initial) {
//         // Drill down to 100m clustering
//         await _drillDownToSubgroup(tappedCluster);
//       } else if (currentLevel == ClusterLevel.subgroup) {
//         if (tappedCluster.isSingleMemory) {
//           // Open single memory
//           final memory = tappedCluster.singleMemory!;
//           widget.onMemorySelected?.call(memory.metadata);
//         } else {
//           // Show memory list popup
//           await _showMemoryListPopup(tappedCluster);
//         }
//       }
//     } catch (e) {
//       debugPrint('Error handling marker tap: $e');
//     }
//   }

//   Future<void> _drillDownToSubgroup(MemoryCluster selectedCluster) async {
//     try {
//       setState(() {
//         this.selectedCluster = selectedCluster;
//         currentLevel = ClusterLevel.subgroup;
//       });

//       // Re-cluster memories in selected cluster with 100m radius
//       currentClusters = MemoryClusteringService.clusterMemories(
//         selectedCluster.memories,
//         MemoryClusteringService.subgroupClusterRadiusM / 1000, // Convert to km
//       );

//       // Generate new arrows for subgroup
//       currentArrows = MemoryClusteringService.generateChronologicalArrows(currentClusters);

//       // Update display
//       await _displayClusters();
//       await _setCameraToFitClusters();

//       debugPrint('Drilled down to ${currentClusters.length} subclusters');
//     } catch (e) {
//       debugPrint('Error drilling down: $e');
//     }
//   }

//   Future<void> _showMemoryListPopup(MemoryCluster cluster) async {
//     final memories = cluster.memories.map((m) => m.metadata).toList();

//     // Sort by date descending
//     memories.sort((a, b) {
//       final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
//       final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
//       return dateB.compareTo(dateA);
//     });

//     // Show popup
//     await showDialog(
//       context: context,
//       builder: (context) => MemoryClusterPopup(
//         memories: memories,
//         onMemorySelected: (memory) {
//           Navigator.of(context).pop();
//           widget.onMemorySelected?.call(memory);
//         },
//       ),
//     );
//   }

//   Future<void> resetToInitialView() async {
//     try {
//       setState(() {
//         currentLevel = ClusterLevel.initial;
//         selectedCluster = null;
//       });

//       // Re-initialize with original memories
//       _initializeClusters();

//       // Update display
//       await _displayClusters();
//       await _setCameraToFitClusters();

//     } catch (e) {
//       debugPrint('Error resetting view: $e');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (isLoading) {
//       return const Center(
//         child: CircularProgressIndicator(),
//       );
//     }

//     if (currentClusters.isEmpty) {
//       return const Center(
//         child: Text(
//           'No memories with location data found',
//           style: TextStyle(fontSize: 16, color: Colors.grey),
//         ),
//       );
//     }

//     return mapbox.MapWidget(
//       key: const ValueKey("memoryGlobeMap"),
//       mapOptions: mapbox.MapOptions(
//         contextMode: mapbox.ContextMode.UNIQUE,
//         constrainMode: mapbox.ConstrainMode.HEIGHT_ONLY,
//         viewportMode: mapbox.ViewportMode.DEFAULT,
//         orientation: mapbox.NorthOrientation.UPWARDS,
//         crossSourceCollisions: true,
//         size: mapbox.Size(
//           width: MediaQuery.of(context).size.width,
//           height: MediaQuery.of(context).size.height,
//         ),
//         pixelRatio: MediaQuery.of(context).devicePixelRatio,
//       ),
//       cameraOptions: mapbox.CameraOptions(
//         center: mapbox.Point(coordinates: mapbox.Position(0, 0)),
//         zoom: 2.0,
//       ),
//       styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
//       textureView: true,
//       onMapCreated: _onMapCreated,
//        onMapLoadErrorListener: (mapLoadingErrorEventData) async {
//         // debugPrint('🗺 Map load error detected: ${mapLoadingErrorEventData.toString()}');

//         try {
//           // final errorMessage = mapLoadingErrorEventData.toString();
//           final connectivityService = Get.find<ConnectivityService>();
//           // errorMessage.toLowerCase().contains('internet');

//           // Check if this is a connectivity-related error
//           //  f (connectivityService.isMapboxConnectivityError(errorMessage)) {
//             // debugPrint('🌐 Map load error is connectivity-related - checking internet status');
//               _setState(MapInitializationState.internetRequired);

//             // Perform enhanced internet check for Mapbox services
//             final hasInternetForMapbox = await connectivityService.hasInternetForMapbox();

//             if(hasInternetForMapbox) {
//               _setState(MapInitializationState.ready);
//               refreshMapView();
//             }

//           // } else {
//           //   debugPrint('❌ Map load error is not connectivity-related - showing error screen');
//           //   debugPrint('❌ Error details: $errorMessage');
//           //   _setState(MapInitializationState.error);
//           // }

//         } catch (e) {
//           debugPrint('❌ Error handling map load error: $e');
//           _setState(MapInitializationState.error);
//         }
//       },

//     );
//   }
// }
