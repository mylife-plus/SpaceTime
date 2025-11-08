import 'package:get/get_navigation/src/routes/get_route.dart';
import 'package:spacetime/app/modules/add_memories/bindings/add_memories.dart';
import 'package:spacetime/app/modules/add_memories/views/add_memories.dart';
import 'package:spacetime/app/modules/contact_groups/bindings/contact_groups_binding.dart';
import 'package:spacetime/app/modules/contact_groups/views/contact_groups_view.dart';
import 'package:spacetime/app/modules/data/bindings/data_binding.dart';
import 'package:spacetime/app/modules/data/views/data_view.dart';
import 'package:spacetime/app/modules/feedback/bindings/feedback_binding.dart';
import 'package:spacetime/app/modules/feedback/views/feedback_view.dart';
import 'package:spacetime/app/modules/get_started/bindings/get_started_binding.dart';
import 'package:spacetime/app/modules/get_started/views/get_started_view.dart';
import 'package:spacetime/app/modules/hashtag_groups/bindings/hashtag_groups_binding.dart';
import 'package:spacetime/app/modules/hashtag_groups/views/hashtag_groups_view.dart';
import 'package:spacetime/app/modules/map/bindings/map_binding.dart';
import 'package:spacetime/app/modules/map/views/map_view.dart';
import 'package:spacetime/app/modules/map/bindings/map_binding_new.dart';
import 'package:spacetime/app/modules/map/views/map_view_new.dart';
import 'package:spacetime/app/modules/memories/bindings/memory_binding.dart';
import 'package:spacetime/app/modules/security/bindings/security_binding.dart';
import 'package:spacetime/app/modules/security/views/security_view.dart';
import 'package:spacetime/app/modules/settings/bindings/settings_binding.dart';
import 'package:spacetime/app/modules/settings/views/settings_view.dart';
import 'package:spacetime/app/modules/ui/bindings/ui_binding.dart';
import 'package:spacetime/app/modules/ui/views/ui_view.dart';
import 'package:spacetime/app/widgets/startup_router.dart';

import '../modules/memories/views/memory_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.STARTUP;

  static final routes = [
    GetPage(
      name: _Paths.STARTUP,
      page: () => const StartupRouter(),
    ),
    GetPage(name: _Paths.MAP, page: () => MapView(), binding: MapBinding()),
    GetPage(
      name: _Paths.MAP_NEW,
      page: () => const MapViewNew(),
      binding: MapBindingNew(),
    ),
    GetPage(
      name: _Paths.SETTINGS,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
    ),
    GetPage(
      name: _Paths.SECURITY,
      page: () => const SecurityView(),
      binding: SecurityBinding(),
    ),
    GetPage(name: _Paths.UI, page: () => const UiView(), binding: UiBinding()),
    GetPage(
      name: _Paths.DATA,
      page: () => const DataView(),
      binding: DataBinding(),
    ),
    GetPage(
      name: _Paths.HASHTAG_GROUPS,
      page: () => const HashtagGroupsView(),
      binding: HashtagGroupsBinding(),
    ),
    GetPage(
      name: _Paths.CONTACT_GROUPS,
      page: () => const ContactGroupsView(),
      binding: ContactGroupsBinding(),
    ),
    GetPage(
      name: _Paths.FEEDBACK,
      page: () => FeedbackView(),
      binding: FeedbackBinding(),
    ),
    GetPage(
      name: _Paths.GET_STARTED,
      page: () => const GetStartedView(),
      binding: GetStartedBinding(),
    ),
    GetPage(
      name: _Paths.MEMORIES,
      page: () => MemoryView(),
      binding: MemoryBinding(),
    ),
    GetPage(
      name: _Paths.ADD_MEMORIES,
      page: () => const AddMemoriesView(),
      binding: AddMemoriesBindings(),
    ),
  ];
}
