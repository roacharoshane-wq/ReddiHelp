import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/media_service.dart';

class MediaAttachmentWidget extends StatefulWidget {
  final int? incidentId;
  final double? lat;
  final double? lon;
  final void Function(List<Map<String, dynamic>> uploadedMedia)? onUploaded;

  const MediaAttachmentWidget({
    super.key,
    this.incidentId,
    this.lat,
    this.lon,
    this.onUploaded,
  });

  @override
  State<MediaAttachmentWidget> createState() => _MediaAttachmentWidgetState();
}

class _MediaAttachmentWidgetState extends State<MediaAttachmentWidget> {
  final MediaService _mediaService = MediaService();
  final List<XFile> _selectedPhotos = [];
  XFile? _selectedVideo;
  bool _uploading = false;
  int _uploadProgress = 0;
  int _uploadTotal = 0;
  String? _error;

  Future<void> _pickPhotosFromCamera() async {
    final files = await _mediaService.pickPhotos(source: ImageSource.camera);
    if (files.isNotEmpty) {
      setState(() {
        _selectedPhotos.addAll(files);
        if (_selectedPhotos.length > 5) {
          _selectedPhotos.removeRange(0, _selectedPhotos.length - 5);
        }
      });
    }
  }

  Future<void> _pickPhotosFromGallery() async {
    final files = await _mediaService.pickPhotos(source: ImageSource.gallery);
    if (files.isNotEmpty) {
      setState(() {
        _selectedPhotos.addAll(files);
        if (_selectedPhotos.length > 5) {
          _selectedPhotos.removeRange(0, _selectedPhotos.length - 5);
        }
      });
    }
  }

  Future<void> _pickVideo() async {
    final file = await _mediaService.pickVideo(source: ImageSource.camera);
    if (file != null) {
      setState(() => _selectedVideo = file);
    }
  }

  void _removePhoto(int index) {
    setState(() => _selectedPhotos.removeAt(index));
  }

  void _removeVideo() {
    setState(() => _selectedVideo = null);
  }

  Future<void> _uploadAll() async {
    if (widget.incidentId == null) {
      setState(() => _error = 'Incident must be created first');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _uploadProgress = 0;
      _uploadTotal = _selectedPhotos.length + (_selectedVideo != null ? 1 : 0);
    });

    final results = <Map<String, dynamic>>[];

    // Upload photos
    if (_selectedPhotos.isNotEmpty) {
      final photoResults = await _mediaService.uploadPhotos(
        files: _selectedPhotos,
        incidentId: widget.incidentId!,
        lat: widget.lat,
        lon: widget.lon,
        onProgress: (completed, total) {
          setState(() => _uploadProgress = completed);
        },
      );
      results.addAll(photoResults);
    }

    // Upload video
    if (_selectedVideo != null) {
      final videoResult = await _mediaService.uploadVideo(
        file: _selectedVideo!,
        incidentId: widget.incidentId!,
      );
      if (videoResult != null) {
        results.add(videoResult);
      }
      setState(() => _uploadProgress = _uploadTotal);
    }

    setState(() => _uploading = false);

    if (results.isNotEmpty) {
      widget.onUploaded?.call(results);
      setState(() {
        _selectedPhotos.clear();
        _selectedVideo = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${results.length} file(s) uploaded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _selectedPhotos.isNotEmpty || _selectedVideo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action buttons
        Row(
          children: [
            _actionButton(
              icon: Icons.camera_alt,
              label: 'Camera',
              onTap: _uploading ? null : _pickPhotosFromCamera,
            ),
            const SizedBox(width: 8),
            _actionButton(
              icon: Icons.photo_library,
              label: 'Gallery',
              onTap: _uploading ? null : _pickPhotosFromGallery,
            ),
            const SizedBox(width: 8),
            if (_selectedVideo == null)
              _actionButton(
                icon: Icons.videocam,
                label: 'Video',
                onTap: _uploading ? null : _pickVideo,
              ),
          ],
        ),

        // Photo count indicator
        if (_selectedPhotos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_selectedPhotos.length}/5 photos selected',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),

        // Photo thumbnails
        if (_selectedPhotos.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedPhotos.length,
              itemBuilder: (ctx, i) => _photoThumbnail(_selectedPhotos[i], i),
            ),
          ),
        ],

        // Video thumbnail
        if (_selectedVideo != null) ...[
          const SizedBox(height: 8),
          _videoThumbnail(_selectedVideo!),
        ],

        // Upload button
        if (hasMedia && !_uploading) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _uploadAll,
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: Text(
                  'Upload ${_selectedPhotos.length + (_selectedVideo != null ? 1 : 0)} file(s)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],

        // Upload progress
        if (_uploading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: _uploadTotal > 0 ? _uploadProgress / _uploadTotal : 0),
          const SizedBox(height: 4),
          Text(
            'Uploading $_uploadProgress of $_uploadTotal...',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],

        // Error
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.teal),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _photoThumbnail(XFile file, int index) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(file.path),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoThumbnail(XFile file) {
    return Stack(
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.videocam, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const Text('(WiFi upload only)',
                  style: TextStyle(fontSize: 10, color: Colors.orange)),
            ],
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _removeVideo,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
