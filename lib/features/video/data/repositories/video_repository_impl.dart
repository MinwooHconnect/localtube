import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import '../../domain/models/video.dart';
import '../../domain/repositories/video_repository.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

class VideoRepositoryImpl extends ChangeNotifier implements VideoRepository {
  List<Video> _videos = [];
  final List<String> _videoExtensions = [
    '.mp4',
    '.avi',
    '.mov',
    '.mkv',
    '.wmv',
    '.flv'
  ];
  bool _isInitialized = false;
  Directory? _thumbnailCacheDir;
  final Map<String, bool> _processingThumbnails = {};
  static const platform = MethodChannel('com.example.albumtube/platform');

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isAndroid) {
      final permissions = [
        Permission.storage,
        Permission.accessMediaLocation,
      ];

      // Android 13 이상인 경우 READ_MEDIA_VIDEO 권한 추가
      if (await _getAndroidSdkVersion() >= 33) {
        permissions.add(Permission.videos);
      }

      for (final permission in permissions) {
        final status = await permission.request();
        if (!status.isGranted) {
          throw Exception('Permission denied: $permission');
        }
      }

      // Android에서는 외부 저장소의 앱별 디렉토리를 사용
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('Failed to get external storage directory');
      }
      _thumbnailCacheDir = Directory(path.join(externalDir.path, 'thumbnails'));
    } else {
      // iOS나 다른 플랫폼에서는 앱의 문서 디렉토리 사용
      final appDir = await getApplicationDocumentsDirectory();
      _thumbnailCacheDir = Directory(path.join(appDir.path, 'thumbnails'));
    }

    try {
      if (!await _thumbnailCacheDir!.exists()) {
        await _thumbnailCacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Error creating thumbnail directory: $e');
      // 폴더 생성 실패 시 캐시 디렉토리 사용
      final cacheDir = await getTemporaryDirectory();
      _thumbnailCacheDir = Directory(path.join(cacheDir.path, 'thumbnails'));
      if (!await _thumbnailCacheDir!.exists()) {
        await _thumbnailCacheDir!.create(recursive: true);
      }
    }

    await _loadLocalVideos();
    _isInitialized = true;
  }

  Future<int> _getAndroidSdkVersion() async {
    try {
      final sdkVersion =
          await platform.invokeMethod<int>('getAndroidSdkVersion');
      return sdkVersion ?? 0;
    } catch (e) {
      debugPrint('Error getting Android SDK version: $e');
      return 0;
    }
  }

  @override
  Future<List<Video>> getVideos({int page = 0, int pageSize = 10}) async {
    if (!_isInitialized) {
      await initialize();
    }

    final startIndex = page * pageSize;
    if (startIndex >= _videos.length) {
      return [];
    }

    final endIndex = (startIndex + pageSize).clamp(0, _videos.length);
    return _videos.sublist(startIndex, endIndex);
  }

  Future<void> _loadLocalVideos() async {
    final List<Video> videos = [];
    if (Platform.isIOS || Platform.isMacOS) {
      final appDir = await getApplicationDocumentsDirectory();
      await _scanDirectory(appDir, videos);
    } else if (Platform.isAndroid) {
      // Android에서는 여러 미디어 디렉토리를 검색
      final directories = [
        Directory('/storage/emulated/0/DCIM'),
        Directory('/storage/emulated/0/Movies'),
        Directory('/storage/emulated/0/Download'),
      ];

      for (final dir in directories) {
        if (await dir.exists()) {
          await _scanDirectory(dir, videos);
        }
      }
    }
    _videos = videos;
    notifyListeners();
  }

  Future<void> _scanDirectory(Directory directory, List<Video> videos) async {
    try {
      final entities = await directory.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is File &&
            _videoExtensions
                .any((ext) => entity.path.toLowerCase().endsWith(ext))) {
          try {
            final stat = await entity.stat();
            videos.add(Video(
              path: entity.path,
              title: path.basename(entity.path),
              dateAdded: stat.modified,
            ));
          } catch (e) {
            debugPrint('Error getting file stats: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory ${directory.path}: $e');
    }
  }

  @override
  Future<Video> generateThumbnail(Video video) async {
    if (video.isThumbnailGenerated) {
      return video;
    }

    if (_processingThumbnails[video.path] == true) {
      return video;
    }

    try {
      _processingThumbnails[video.path] = true;

      // Verify video file exists
      final videoFile = File(video.path);
      if (!await videoFile.exists()) {
        print('Video file not found: ${video.path}');
        _processingThumbnails.remove(video.path);
        return video;
      }

      final videoFileName = video.path.split('/').last;
      final thumbnailFileName = '${videoFileName.hashCode}.jpg';
      final thumbnailPath = '${_thumbnailCacheDir!.path}/$thumbnailFileName';

      final thumbnailFile = File(thumbnailPath);
      if (await thumbnailFile.exists()) {
        // Verify the existing thumbnail is valid
        if (await thumbnailFile.length() > 0) {
          _processingThumbnails.remove(video.path);
          return video.copyWith(
            thumbnailPath: thumbnailPath,
            isThumbnailGenerated: true,
          );
        } else {
          // Delete invalid thumbnail
          await thumbnailFile.delete();
        }
      }

      // Try FFmpeg first
      debugPrint('Generating thumbnail using FFmpeg for: ${video.path}');
      final session = await FFmpegKit.execute(
          '-y -i "${video.path}" -vframes 1 -an -s 300x169 -ss 0 "$thumbnailPath"');

      final returnCode = await session.getReturnCode();
      var success = ReturnCode.isSuccess(returnCode);

      if (success &&
          await thumbnailFile.exists() &&
          await thumbnailFile.length() > 0) {
        debugPrint(
            'FFmpeg successfully generated thumbnail at: $thumbnailPath');
      } else {
        final logs = await session.getLogs();
        debugPrint('FFmpeg failed with logs: $logs');

        // Try video_thumbnail as fallback
        debugPrint('Trying video_thumbnail as fallback...');
        final uint8list = await VideoThumbnail.thumbnailData(
          video: video.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 300,
          quality: 75,
          timeMs: 0,
        );

        if (uint8list != null && uint8list.isNotEmpty) {
          await thumbnailFile.writeAsBytes(uint8list);
          success =
              await thumbnailFile.exists() && await thumbnailFile.length() > 0;
          if (success) {
            debugPrint(
                'video_thumbnail successfully generated thumbnail at: $thumbnailPath');
          }
        }
      }

      _processingThumbnails.remove(video.path);

      if (success) {
        final updatedVideo = video.copyWith(
          thumbnailPath: thumbnailPath,
          isThumbnailGenerated: true,
        );

        final index = _videos.indexWhere((v) => v.path == video.path);
        if (index != -1) {
          _videos[index] = updatedVideo;
          notifyListeners();
        }

        return updatedVideo;
      }

      debugPrint('Failed to generate thumbnail using both methods');
      return video;
    } catch (e, stackTrace) {
      print('Error generating thumbnail for: ${video.path}');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      _processingThumbnails.remove(video.path);
      return video;
    }
  }

  @override
  Future<void> addVideo(String path) async {
    final file = File(path);
    final dateAdded = file.lastModifiedSync();
    final title = DateFormat('yyyy-MM-dd HH:mm:ss').format(dateAdded);

    final video = Video(
      path: path,
      title: title,
      dateAdded: dateAdded,
    );

    _videos.add(video);
    _videos.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
  }

  @override
  Future<void> deleteVideo(String path) async {
    final video = _videos.firstWhere((video) => video.path == path);
    if (video.thumbnailPath?.isNotEmpty ?? false) {
      final thumbnailFile = File(video.thumbnailPath!);
      if (await thumbnailFile.exists()) {
        await thumbnailFile.delete();
      }
    }
    _videos.removeWhere((video) => video.path == path);
  }

  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final thumbnailPath = await _getThumbnailPath(videoPath);
      if (thumbnailPath == null) return null;

      final command =
          '-i "$videoPath" -ss 00:00:01 -vframes 1 -y "$thumbnailPath"';
      debugPrint('Requesting thumbnail for: $videoPath');
      debugPrint('Loading ffmpeg-kit-flutter.');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('Thumbnail generated successfully at: $thumbnailPath');
        return thumbnailPath;
      } else {
        final logs = await session.getLogs();
        debugPrint('Failed to generate thumbnail. FFmpeg logs: $logs');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('Error generating thumbnail: $e\n$stackTrace');
      return null;
    }
  }

  Future<String?> _getThumbnailPath(String videoPath) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        debugPrint('Video file does not exist: $videoPath');
        return null;
      }

      final videoFileName = path.basename(videoPath);
      final thumbnailFileName =
          '${path.basenameWithoutExtension(videoFileName)}_thumb.jpg';
      final thumbnailPath =
          path.join(_thumbnailCacheDir!.path, thumbnailFileName);

      return thumbnailPath;
    } catch (e) {
      debugPrint('Error getting thumbnail path: $e');
      return null;
    }
  }
}
