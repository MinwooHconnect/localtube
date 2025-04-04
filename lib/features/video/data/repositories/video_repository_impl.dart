import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_compress/video_compress.dart';
import 'package:localtube/features/video/domain/models/video.dart';
import 'package:localtube/features/video/domain/repositories/video_repository.dart';

class VideoRepositoryImpl implements VideoRepository {
  final List<Video> _videos = [];
  final List<String> _supportedExtensions = [
    '.mp4',
    '.avi',
    '.mov',
    '.mkv',
    '.wmv',
    '.flv',
    '.webm',
  ];

  @override
  Future<void> initialize() async {
    if (Platform.isAndroid) {
      if (await _getAndroidSdkVersion() >= 33) {
        await Permission.videos.request();
        await Permission.photos.request();
      } else {
        await Permission.storage.request();
      }
    }

    final cacheDir = await getTemporaryDirectory();
    final thumbnailDir = Directory('${cacheDir.path}/thumbnails');
    if (!await thumbnailDir.exists()) {
      await thumbnailDir.create(recursive: true);
    }
  }

  Future<int> _getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    final sdkVersion =
        await const MethodChannel('com.example.albumtube/android')
            .invokeMethod<int>('getAndroidSdkVersion');
    return sdkVersion ?? 0;
  }

  @override
  Future<List<Video>> getVideos({int page = 0, int pageSize = 10}) async {
    if (_videos.isEmpty) {
      await _loadLocalVideos();
    }
    final start = page * pageSize;
    final end = start + pageSize;
    if (start >= _videos.length) return [];
    return _videos.sublist(start, end.clamp(0, _videos.length));
  }

  Future<void> _loadLocalVideos() async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final appDir = await getApplicationDocumentsDirectory();
        await _scanDirectory(appDir);
      } else if (Platform.isAndroid) {
        final directories = [
          '/storage/emulated/0/DCIM',
          '/storage/emulated/0/Movies',
          '/storage/emulated/0/Download',
        ];

        for (final dir in directories) {
          final directory = Directory(dir);
          if (await directory.exists()) {
            await _scanDirectory(directory);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading videos: $e');
      rethrow;
    }
  }

  Future<void> _scanDirectory(Directory directory) async {
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final extension = entity.path.toLowerCase().split('.').last;
          if (_supportedExtensions.contains('.$extension')) {
            try {
              final stats = await entity.stat();
              final video = Video(
                id: entity.path,
                path: entity.path,
                duration: const Duration(seconds: 0), // Will be updated later
                dateAdded: stats.modified,
                size: stats.size,
              );
              if (!_videos.any((v) => v.path == video.path)) {
                _videos.add(video);
              }
            } catch (e) {
              debugPrint('Error getting file stats: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory: $e');
    }
  }

  @override
  Future<Video> generateThumbnail(Video video) async {
    if (video.isThumbnailGenerated && video.thumbnailPath != null) {
      return video;
    }

    try {
      final file = File(video.path);
      if (!await file.exists()) {
        throw Exception('Video file not found');
      }

      final mediaInfo = await VideoCompress.getMediaInfo(video.path);
      final aspectRatio = mediaInfo.height! / mediaInfo.width!;

      final thumbnailFile = await VideoCompress.getFileThumbnail(
        video.path,
        quality: 50,
        position: -1,
      );

      return video.copyWith(
        thumbnailPath: thumbnailFile.path,
        duration: Duration(milliseconds: mediaInfo.duration!.toInt()),
        isThumbnailGenerated: true,
      );
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      // Fallback to video_thumbnail package
      try {
        final thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: video.path,
          thumbnailPath: (await getTemporaryDirectory()).path,
          imageFormat: ImageFormat.JPEG,
          quality: 50,
        );

        return video.copyWith(
          thumbnailPath: thumbnailPath,
          isThumbnailGenerated: thumbnailPath != null,
        );
      } catch (e) {
        debugPrint('Error generating thumbnail with fallback: $e');
        rethrow;
      }
    }
  }

  @override
  Future<void> addVideo(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final stats = await file.stat();
      final video = Video(
        id: path,
        path: path,
        duration: const Duration(seconds: 0),
        dateAdded: stats.modified,
        size: stats.size,
      );
      if (!_videos.any((v) => v.path == video.path)) {
        _videos.add(video);
      }
    }
  }

  @override
  Future<void> deleteVideo(String path) async {
    _videos.removeWhere((video) => video.path == path);
  }
}
