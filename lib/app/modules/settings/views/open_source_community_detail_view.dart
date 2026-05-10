import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/widgets/appbar.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config/app_images.dart';
import '../../../widgets/color_changing_loader.dart';

class OpenSourceCommunityDetailView extends StatelessWidget {
  OpenSourceCommunityDetailView({
    super.key,
    required this.title,
    required this.url,
    this.appBarIcon,
  });

  final String title;
  final String url;
  final Widget? appBarIcon;
  final RxBool _loading = true.obs;

  late final WebViewController _controller =
      WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => _loading.value = true,
            onPageFinished: (_) => _loading.value = false,
          ),
        )
        ..loadRequest(Uri.parse(url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: title,
        icon: appBarIcon ?? Image.asset(AppImages.feedback),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          Obx(
            () =>
                _loading.value
                    ? const ColorChangingLoader()
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
