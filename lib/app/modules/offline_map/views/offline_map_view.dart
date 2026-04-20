// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
// import '../controllers/offline_map_controller.dart';

// class OfflineMapView extends GetView<OfflineMapController> {
//   const OfflineMapView({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Offline Maps'),
//         backgroundColor: Colors.blue,
//         foregroundColor: Colors.white,
//         actions: [
//           Obx(() => IconButton(
//             icon: Icon(
//               controller.offlineMapService.isOfflineReady.value
//                 ? Icons.wifi_off
//                 : Icons.cloud_download,
//             ),
//             onPressed: controller.offlineMapService.isOfflineReady.value
//                 ? controller.toggleOfflineMode
//                 : null,
//             tooltip: controller.offlineMapService.isOfflineReady.value
//                 ? 'Toggle Offline Mode'
//                 : 'Download Required',
//           )),
//         ],
//       ),
//       body: Column(
//         children: [
//           // Map area
//           Expanded(
//             flex: 3,
//             child: Obx(() {
//               if (controller.offlineMapService.isOfflineReady.value) {
//                 return _buildOfflineMap();
//               } else {
//                 return _buildDownloadInterface();
//               }
//             }),
//           ),

//           // Progress and status area
//           Expanded(
//             flex: 1,
//             child: _buildProgressSection(),
//           ),
//         ],
//       ),
//     );
//   }

//   /// Build the offline map widget
//   Widget _buildOfflineMap() {
//     return Container(
//       decoration: BoxDecoration(
//         border: Border.all(color: Colors.green, width: 2),
//         borderRadius: BorderRadius.circular(8),
//       ),
//       margin: const EdgeInsets.all(8),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(6),
//         child: MapWidget(
//           key: const ValueKey("offlineMapWidget"),
//           styleUri: MapboxStyles.MAPBOX_STREETS,
//           cameraOptions: CameraOptions(
//             center: Point(coordinates: Position(73.0479, 33.6844)), // Islamabad
//             zoom: 12.0,
//           ),
//           onMapCreated: controller.onOfflineMapCreated,
//         ),
//       ),
//     );
//   }

//   /// Build the download interface
//   Widget _buildDownloadInterface() {
//     return Container(
//       margin: const EdgeInsets.all(16),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(
//             Icons.cloud_download,
//             size: 64,
//             color: Colors.blue.shade300,
//           ),
//           const SizedBox(height: 16),
//           Text(
//             'text_download_offline_maps'.tr,
//             style: Get.textTheme.headlineSmall?.copyWith(
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             'Download map tiles for offline use.\nRequires at least 40,000 tiles.',
//             textAlign: TextAlign.center,
//             style: Get.textTheme.bodyMedium?.copyWith(
//               color: Colors.grey.shade600,
//             ),
//           ),
//           const SizedBox(height: 24),
//           Obx(() => SizedBox(
//             width: double.infinity,
//             child: ElevatedButton.icon(
//               onPressed: controller.offlineMapService.isDownloading.value
//                   ? null
//                   : controller.startDownload,
//               icon: controller.offlineMapService.isDownloading.value
//                   ? const SizedBox(
//                       width: 16,
//                       height: 16,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Icon(Icons.download),
//               label: Text(
//                 controller.offlineMapService.isDownloading.value
//                     ? 'Downloading...'
//                     : 'Download Maps',
//               ),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Colors.blue,
//                 foregroundColor: Colors.white,
//                 padding: const EdgeInsets.symmetric(vertical: 12),
//               ),
//             ),
//           )),
//         ],
//       ),
//     );
//   }

//   /// Build the progress section
//   Widget _buildProgressSection() {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.grey.shade50,
//         border: Border(top: BorderSide(color: Colors.grey.shade300)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Status text
//           Obx(() => Text(
//             controller.offlineMapService.downloadStatusText.value,
//             style: Get.textTheme.titleSmall?.copyWith(
//               fontWeight: FontWeight.w500,
//             ),
//           )),
//           const SizedBox(height: 12),

//           // Style pack progress
//           Obx(() => Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     'text_style_pack'.tr,
//                     style: Get.textTheme.bodySmall,
//                   ),
//                   Text(
//                     '${(controller.offlineMapService.stylePackProgress.value * 100).toStringAsFixed(1)}%',
//                     style: Get.textTheme.bodySmall?.copyWith(
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 4),
//               LinearProgressIndicator(
//                 value: controller.offlineMapService.stylePackProgress.value,
//                 backgroundColor: Colors.grey.shade300,
//                 valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
//               ),
//             ],
//           )),
//           const SizedBox(height: 12),

//           // Tile region progress
//           Obx(() => Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     'text_map_tiles'.tr,
//                     style: Get.textTheme.bodySmall,
//                   ),
//                   Text(
//                     '${controller.offlineMapService.downloadedTileCount.value} tiles (${(controller.offlineMapService.tileRegionProgress.value * 100).toStringAsFixed(1)}%)',
//                     style: Get.textTheme.bodySmall?.copyWith(
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 4),
//               LinearProgressIndicator(
//                 value: controller.offlineMapService.tileRegionProgress.value,
//                 backgroundColor: Colors.grey.shade300,
//                 valueColor: AlwaysStoppedAnimation<Color>(
//                   controller.offlineMapService.downloadedTileCount.value >= 40000
//                       ? Colors.green
//                       : Colors.orange,
//                 ),
//               ),
//             ],
//           )),

//           // Action buttons
//           const SizedBox(height: 12),
//           Row(
//             children: [
//               Expanded(
//                 child: Obx(() => OutlinedButton.icon(
//                   onPressed: controller.offlineMapService.isDownloading.value
//                       ? null
//                       : controller.clearOfflineData,
//                   icon: const Icon(Icons.delete_outline),
//                   label: const Text('Clear Data'),
//                   style: OutlinedButton.styleFrom(
//                     foregroundColor: Colors.red,
//                   ),
//                 )),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Obx(() => ElevatedButton.icon(
//                   onPressed: controller.offlineMapService.isOfflineReady.value
//                       ? controller.toggleOfflineMode
//                       : null,
//                   icon: Icon(
//                     controller.isOfflineModeEnabled.value
//                         ? Icons.wifi
//                         : Icons.wifi_off,
//                   ),
//                   label: Text(
//                     controller.isOfflineModeEnabled.value
//                         ? 'Go Online'
//                         : 'Go Offline',
//                   ),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: controller.isOfflineModeEnabled.value
//                         ? Colors.green
//                         : Colors.orange,
//                     foregroundColor: Colors.white,
//                   ),
//                 )),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }
