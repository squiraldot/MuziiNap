import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:get/get.dart';

import 'common_dialog_widget.dart';

void showQrCodeDialog(BuildContext context, String url, String title) {
  Get.dialog(
    CommonDialog(
      maxWidth: 330,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            SizedBox(
              width: 250,
              height: 250,
              child: Center(
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 250.0,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Get.back(),
                child: Text('close'.tr),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
