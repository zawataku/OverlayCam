import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  File? _overlayImage;
  File? _capturedImage;
  final GlobalKey _globalKey = GlobalKey();
  bool _isCapturing = false;

  // オーバーレイの状態
  Matrix4 _matrix = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage, // 古いAndroidや一般的なストレージ用
    ].request();

    if (statuses[Permission.camera] == PermissionStatus.granted) {
       _initializeCamera();
    } else {
       // 権限拒否の処理
       print("カメラの権限が拒否されました");
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    
    // 背面カメラを選択
    final camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('カメラの初期化エラー: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _overlayImage = File(pickedFile.path);
        _matrix = Matrix4.identity(); // 変形をリセット
      });
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
        return;
    }
    
    setState(() {
      _isCapturing = true; 
    });

    try {
        // 1. 高解像度の写真を撮影
        final XFile image = await _controller!.takePicture();
        final File imageFile = File(image.path);
        
        // 2. 表示用に画像をプリロード
        final ImageProvider imageProvider = FileImage(imageFile);
        await precacheImage(imageProvider, context);

        // 3. プレビューの代わりに撮影した画像を表示
        setState(() {
          _capturedImage = imageFile;
        });

        // UIが新しいフレームを描画するのを待機
        // precacheでデータは準備できているが、ウィジェットのマウントと描画が必要
        await Future.delayed(const Duration(milliseconds: 300));

        // 4. ウィジェットツリーをキャプチャ (RepaintBoundary)
        RenderRepaintBoundary? boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        
        if (boundary != null) {
          // 準備ができていない場合のリトライロジック
          ui.Image compositeImage;
          try {
             compositeImage = await boundary.toImage(pixelRatio: 3.0);
          } catch (retryError) {
             await Future.delayed(const Duration(milliseconds: 100));
             compositeImage = await boundary.toImage(pixelRatio: 3.0);
          }
          
          ByteData? byteData = await compositeImage.toByteData(format: ui.ImageByteFormat.png);
          
          if (byteData != null) {
             final directory = await getTemporaryDirectory();
             final String filePath = '${directory.path}/overlay_capture_${DateTime.now().millisecondsSinceEpoch}.png';
             final File file = File(filePath);
             await file.writeAsBytes(byteData.buffer.asUint8List());

             // 5. ギャラリーに保存
             await Gal.putImage(file.path, album: 'OverlayCamera');
             
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('ギャラリーに保存しました！')),
               );
             }
          }
        }
    } catch (e) {
        print('撮影エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('エラー: $e')),
          );
        }
    } finally {
        // 6. プレビューを復元
        if (mounted) {
           setState(() {
              _capturedImage = null;
              _isCapturing = false;
           });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OverlayCam'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // コンテンツエリア (カメラ/画像 + オーバーレイ) RepaintBoundaryでラップ
                Center(
                  child: RepaintBoundary(
                    key: _globalKey,
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Stack(
                         fit: StackFit.expand,
                         children: [
                           // レイヤー 1: 背景 (カメラプレビューまたは撮影画像)
                           if (_capturedImage != null)
                              Image.file(_capturedImage!, fit: BoxFit.cover)
                           else 
                              CameraPreview(_controller!),
                              
                           // レイヤー 2: ジェスチャー付きオーバーレイ画像
                           if (_overlayImage != null)
                              LayoutBuilder(
                                builder: (ctx, constraints) {
                                  return MatrixGestureDetector(
                                    key: ValueKey(_overlayImage!.path), // 画像変更時にリセットを強制
                                    onMatrixUpdate: (m, tm, sm, rm) {
                                      setState(() {
                                        _matrix = m;
                                      });
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      alignment: Alignment.center,
                                      color: Colors.transparent, 
                                      child: Transform(
                                        transform: _matrix,
                                        child: Image.file(
                                          _overlayImage!,
                                          width: 300, 
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                         ],
                      ),
                    ),
                  ),
                ),
                
                if (_isCapturing)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '写真を合成中...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 下部コントロールエリア
          Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: SafeArea( // ホームインジケーターと重ならないようにする
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ギャラリーボタン
                  IconButton(
                    icon: const Icon(Icons.photo_library, size: 32),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _isCapturing ? null : _pickImage,
                  ),
                  
                  // Shutter Button
                  FloatingActionButton(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    onPressed: _captureImage,
                    child: const Icon(Icons.camera_alt),
                  ),
                  
                  // Spacer/Placeholder for balance or future features
                  const SizedBox(width: 48), 
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
