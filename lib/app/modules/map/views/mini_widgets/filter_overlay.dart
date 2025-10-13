// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:spacetime/app/modules/map/views/mini_widgets/filter_chip_label.dart';
// import '../../../../config/app_images.dart';
// import '../../controllers/map_controller.dart';
// import 'filter_fields.dart';
// import 'package:spacetime/app/widgets/filter_section.dart';

// class MapFilterOverlay extends StatelessWidget {
//   const MapFilterOverlay({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final controller = Get.find<MapController>();

//     return Stack(
//       children: [
//         Positioned.fill(
//           child: GestureDetector(
//             onTap: () {
//               Get.back();
//               controller.closeFilter();
//             },
//             child: Container(color: Colors.black.withOpacity(0.5)),
//           ),
//         ),

//         Positioned(
//           top: 0,
//           left: 0,
//           right: 0,
//           child: GestureDetector(
//             onTap: () {}, // absorb touches
//             child: FilterPanel(
//               onReset: controller.closeFilter,
//               onApply: () => print("Filter tapped"),
//               children: const [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: FilterTextFieldRow(
//                         imagePath: AppImages.calendar,
//                         hint: 'from date',
//                       ),
//                     ),
//                     SizedBox(width: 5),
//                     Expanded(
//                       child: FilterTextFieldRow(
//                         imagePath: AppImages.calendar,
//                         hint: 'to date',
//                       ),
//                     ),
//                   ],
//                 ),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: FilterTextFieldRow(
//                         imagePath: AppImages.location,
//                         hint: 'location',
//                       ),
//                     ),
//                     SizedBox(width: 5),
//                     Expanded(
//                       child: FilterTextFieldRow(
//                         imagePath: AppImages.location,
//                         hint: 'radius',
//                       ),
//                     ),
//                   ],
//                 ),
//                 FilterTextFieldRow(
//                   imagePath: AppImages.category2,
//                   hint: 'search Places',
//                 ),
//                 FilterTextFieldRow(
//                   imagePath: AppImages.tag,
//                   hint: 'search Hashtags',
//                 ),
//                 FilterChipLabel(label: '#holiday'),
//                 FilterTextFieldRow(
//                   imagePath: AppImages.mention,
//                   hint: 'search Contacts',
//                 ),
//                 FilterChipLabel(label: '@Markus'),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }
