import '../models/video.dart';

abstract class VideoRepository {
  Future<List<Video>> getVideos({int page = 0, int pageSize = 10});
  Future<void> addVideo(String path);
  Future<void> deleteVideo(String path);
  Future<void> initialize();
  Future<Video> generateThumbnail(Video video);
}
