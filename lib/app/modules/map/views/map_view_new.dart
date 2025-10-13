import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/map_controller_new.dart';
import 'mini_widgets/map_view_widget_new.dart';

class MapViewNew extends GetView<MapControllerNew> {
  const MapViewNew({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MapViewWidgetNew();
  }
}
