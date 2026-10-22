import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:get/get.dart';

import 'Search/search_screen_controller.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;
  bool _isProcessing = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _selectedCamera = _cameras.first;
        await _initCameraController(_selectedCamera!);
      } else {
        setState(() {
          _errorMessage = "No cameras found on this device.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load cameras.\n$e";
      });
    }
  }

  Future<void> _initCameraController(CameraDescription camera) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    _cameraController = CameraController(camera, ResolutionPreset.high, enableAudio: false);
    
    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {});
      _cameraController!.startImageStream((image) async {
        if (_isProcessing) return;
        _isProcessing = true;
        try {
          final zxing.DecodeParams params = zxing.DecodeParams(
            imageFormat: image.format.group == ImageFormatGroup.yuv420 ? zxing.ImageFormat.lum : zxing.ImageFormat.rgb,
            format: zxing.Format.any,
            width: image.width,
            height: image.height,
          );
          final zxing.Code result = await zxing.zx.processCameraImage(image, params);
          if (result.isValid && result.text != null && result.text!.contains('youtube.com')) {
            _cameraController!.stopImageStream();
            Get.back();
            Get.find<SearchScreenController>().filterLinks(Uri.parse(result.text!));
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to initialize camera.\n$e";
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
      ),
      body: Stack(
        children: [
          if (_errorMessage.isNotEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                      );
                      if (result != null && result.files.single.path != null) {
                        final xfile = XFile(result.files.single.path!);
                        final zxing.DecodeParams params = zxing.DecodeParams(
                          imageFormat: zxing.ImageFormat.rgb,
                          format: zxing.Format.any,
                        );
                        final zxing.Code code = await zxing.zx.readBarcodeImagePath(xfile, params);
                        if (code.isValid && code.text != null && code.text!.contains('youtube.com')) {
                          Get.back();
                          Get.find<SearchScreenController>().filterLinks(Uri.parse(code.text!));
                        }
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('Scan from Image File'),
                  ),
                ],
              ),
            )
          else if (_cameraController != null && _cameraController!.value.isInitialized)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(child: CircularProgressIndicator()),
          
          if (_cameras.isNotEmpty)
            Positioned(
              bottom: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CameraDescription>(
                    dropdownColor: Colors.black87,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    value: _selectedCamera,
                    items: _cameras.map((camera) {
                      return DropdownMenuItem<CameraDescription>(
                        value: camera,
                        child: Text(camera.name),
                      );
                    }).toList(),
                    onChanged: (CameraDescription? newCamera) {
                      if (newCamera != null && newCamera != _selectedCamera) {
                        setState(() {
                          _selectedCamera = newCamera;
                        });
                        _initCameraController(newCamera);
                      }
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
