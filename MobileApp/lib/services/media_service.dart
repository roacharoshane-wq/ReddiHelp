import 'dart:convert';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import 'sync_service.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  final ImagePicker _picker = ImagePicker();
  static const int _maxPhotos = 5;
  static const int _maxVideoSeconds = 30;
  static const int _maxImageBytes = 500 * 1024; // 500KB after compression

  Future<bool> _isLikelyOnWifi() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('wi-fi') ||
            name == 'en0' ||
            name.startsWith('wl')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Pick up to [maxPhotos] images from camera or gallery.
  Future<List<XFile>> pickPhotos(
      {ImageSource source = ImageSource.gallery}) async {
    if (source == ImageSource.camera) {
      final file =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      return file != null ? [file] : [];
    }
    final files =
        await _picker.pickMultiImage(imageQuality: 80, limit: _maxPhotos);
    return files.take(_maxPhotos).toList();
  }

  /// Pick a video (max 30 seconds).
  Future<XFile?> pickVideo({ImageSource source = ImageSource.camera}) async {
    return await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: _maxVideoSeconds),
    );
  }

  /// Compress an image to max 500KB.
  Future<File?> compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 1024,
      minHeight: 1024,
    );

    if (result == null) return null;

    // If still too large, compress more aggressively
    final resultFile = File(result.path);
    if (await resultFile.length() > _maxImageBytes) {
      final secondPass = await FlutterImageCompress.compressAndGetFile(
        result.path,
        '${dir.path}/compressed2_${DateTime.now().millisecondsSinceEpoch}.jpg',
        quality: 40,
        minWidth: 800,
        minHeight: 800,
      );
      if (secondPass != null) return File(secondPass.path);
    }

    return resultFile;
  }

  /// Upload a single file to the backend via pre-signed URL flow.
  /// Returns the media record or null on failure.
  Future<Map<String, dynamic>?> uploadFile({
    required File file,
    required String contentType,
    required int incidentId,
    double? lat,
    double? lon,
  }) async {
    try {
      final headers = await ApiService.getHeaders();

      // Step 1: Get pre-signed URL
      final presignResponse = await http.post(
        Uri.parse('${ApiService.baseUrl}/media/presign'),
        headers: headers,
        body: json.encode({
          'filename': file.path.split('/').last,
          'contentType': contentType,
          'incidentId': incidentId,
        }),
      );

      if (presignResponse.statusCode != 200) {
        print('⚠️ [Media] Pre-sign failed: ${presignResponse.statusCode}');
        return null;
      }

      final presignData = json.decode(presignResponse.body);
      final uploadUrl = presignData['uploadUrl'] as String;
      final mediaId = presignData['mediaId'];

      // Step 2: Upload file
      final uploadRequest = http.MultipartRequest('PUT', Uri.parse(uploadUrl));
      uploadRequest.headers.addAll(headers);
      uploadRequest.files
          .add(await http.MultipartFile.fromPath('file', file.path));

      final uploadResponse = await uploadRequest.send();

      if (uploadResponse.statusCode == 200) {
        print('✅ [Media] File uploaded: mediaId=$mediaId');
        return {
          'mediaId': mediaId,
          'storageKey': presignData['storageKey'],
          'incidentId': incidentId,
        };
      } else {
        print('⚠️ [Media] Upload failed: ${uploadResponse.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [Media] Upload error: $e');
      return null;
    }
  }

  /// Upload multiple photos for an incident. Compresses each before upload.
  /// [onProgress] reports (completed, total).
  Future<List<Map<String, dynamic>>> uploadPhotos({
    required List<XFile> files,
    required int incidentId,
    double? lat,
    double? lon,
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <Map<String, dynamic>>[];
    final total = files.length;
    int completed = 0;

    for (final xFile in files) {
      final original = File(xFile.path);
      final compressed = await compressImage(original);
      final toUpload = compressed ?? original;

      final result = await uploadFile(
        file: toUpload,
        contentType: 'image/jpeg',
        incidentId: incidentId,
        lat: lat,
        lon: lon,
      );

      completed++;
      onProgress?.call(completed, total);

      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }

  /// Upload a video. Checks WiFi-only restriction by default.
  Future<Map<String, dynamic>?> uploadVideo({
    required XFile file,
    required int incidentId,
    bool wifiOnly = true,
  }) async {
    if (wifiOnly) {
      final onWifi = await _isLikelyOnWifi();
      if (!onWifi) {
        print('⚠️ [Media] Video upload skipped — WiFi only');
        // Queue for later upload
        await SyncService().enqueue(
          idempotencyKey:
              'video_${incidentId}_${DateTime.now().millisecondsSinceEpoch}',
          action: 'UPLOAD_VIDEO',
          resource: 'media',
          data: {
            'filePath': file.path,
            'incidentId': incidentId,
          },
        );
        return null;
      }
    }

    return await uploadFile(
      file: File(file.path),
      contentType: 'video/mp4',
      incidentId: incidentId,
    );
  }
}
