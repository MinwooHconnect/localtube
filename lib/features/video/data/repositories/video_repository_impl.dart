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
  late final Directory _thumbnailCacheDir;
  final Map<String, bool> _processingThumbnails = {};

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isAndroid) {
      final permissions = <Permission>[
        Permission.storage,
        Permission.accessMediaLocation,
      ];

      for (final permission in permissions) {
        final status = await permission.status;
        if (status.isDenied) {
          final result = await permission.request();
          if (!result.isGranted) {
            print('Permission denied: $permission');
            throw Exception('All permissions are required to access videos');
          }
        }
      }
    } else {
      final storageStatus = await Permission.storage.request();
      final photosStatus = await Permission.photos.request();

      if (!storageStatus.isGranted || !photosStatus.isGranted) {
        throw Exception(
            'Storage and media permissions are required to access videos');
      }
    }

    if (Platform.isAndroid) {
      _thumbnailCacheDir = Directory(
          '/storage/emulated/0/Android/data/com.example.localtube/thumbnails');
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _thumbnailCacheDir = Directory('${appDir.path}/thumbnails');
    }

    if (!await _thumbnailCacheDir.exists()) {
      await _thumbnailCacheDir.create(recursive: true);
    }

    await _loadLocalVideos();
    _isInitialized = true;
  }

  Future<int> _getAndroidSdkVersion() async {
    try {
      const platform = MethodChannel('com.example.localtube/platform');
      final sdkInt = await platform.invokeMethod<int>('getAndroidSdkVersion');
      return sdkInt ?? 0;
    } catch (e) {
      print('Error getting Android SDK version: $e');
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
    // initialize()에서 이미 권한을 확인했으므로 여기서는 생략
    final directories = <Directory>[];

    if (Platform.isIOS || Platform.isMacOS) {
      final documentsDir = await getApplicationDocumentsDirectory();
      directories.add(Directory(documentsDir.path));
    } else if (Platform.isAndroid) {
      directories.add(Directory('/storage/emulated/0/Download'));
      directories.add(Directory('/storage/emulated/0/DCIM'));
      directories.add(Directory('/storage/emulated/0/Movies'));
    }

    final videos = <Video>[];
    for (final directory in directories) {
      if (await directory.exists()) {
        await _scanDirectory(directory, videos);
      }
    }

    _videos = videos;
    notifyListeners();
  }

  Future<void> _scanDirectory(Directory directory, List<Video> videos) async {
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final extension =
              entity.path.toLowerCase().substring(entity.path.lastIndexOf('.'));
          if (_videoExtensions.contains(extension)) {
            final dateAdded = entity.lastModifiedSync();
            final title = path.basename(entity.path);

            videos.add(
              Video(
                path: entity.path,
                title: title,
                dateAdded: dateAdded,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error scanning directory: ${directory.path}, Error: $e');
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
      final thumbnailPath = '${_thumbnailCacheDir.path}/$thumbnailFileName';

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
          path.join(_thumbnailCacheDir.path, thumbnailFileName);

      return thumbnailPath;
    } catch (e) {
      debugPrint('Error getting thumbnail path: $e');
      return null;
    }
  }
}
