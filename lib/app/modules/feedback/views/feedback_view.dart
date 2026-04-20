import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config/app_images.dart';
import '../../../config/app_text.dart';
import '../../../widgets/color_changing_loader.dart';
import '../controllers/feedback_controller.dart';

class FeedbackView extends GetView<FeedbackController> {
  FeedbackView({super.key});

  final loading = true.obs;

  late final WebViewController _controller =
      WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => loading.value = true,
            onPageFinished: (_) => loading.value = false,
          ),
        )
        ..loadRequest(Uri.parse(AppTexts.web));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'title_literal_feedback'.tr,
        icon: Image.asset(AppImages.feedback),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          Obx(
            () =>
                loading.value
                    ? const ColorChangingLoader()
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
