import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/models/video.dart';
import '../../domain/repositories/video_repository.dart';
import 'video_event.dart';
import 'video_state.dart';

class VideoBloc extends Bloc<VideoEvent, VideoState> {
  final VideoRepository videoRepository;
  int _currentPage = 0;
  static const int _pageSize = 10;

  VideoBloc({required this.videoRepository}) : super(VideoInitial()) {
    on<LoadVideos>(_onLoadVideos);
    on<LoadMoreVideos>(_onLoadMoreVideos);
    on<AddVideo>(_onAddVideo);
    on<DeleteVideo>(_onDeleteVideo);
    on<GenerateThumbnail>(_onGenerateThumbnail);
  }

  Future<void> _onLoadVideos(LoadVideos event, Emitter<VideoState> emit) async {
    try {
      emit(const VideoLoading());
      await videoRepository.initialize();
      _currentPage = 0;
      final videos = await videoRepository.getVideos(
          page: _currentPage, pageSize: _pageSize);
      final hasReachedEnd = videos.length < _pageSize;
      emit(VideoLoaded(videos: videos, hasReachedEnd: hasReachedEnd));
    } catch (e) {
      emit(VideoError(e.toString()));
    }
  }

  Future<void> _onLoadMoreVideos(
      LoadMoreVideos event, Emitter<VideoState> emit) async {
    try {
      if (state is VideoLoaded) {
        final currentState = state as VideoLoaded;
        if (currentState.hasReachedEnd) return;

        emit(VideoLoading(
            currentVideos: currentState.videos, isFirstLoad: false));
        _currentPage++;

        final newVideos = await videoRepository.getVideos(
            page: _currentPage, pageSize: _pageSize);
        final hasReachedEnd = newVideos.isEmpty || newVideos.length < _pageSize;

        emit(VideoLoaded(
          videos: [...currentState.videos, ...newVideos],
          hasReachedEnd: hasReachedEnd,
        ));
      }
    } catch (e) {
      if (state is VideoLoaded) {
        final currentVideos = (state as VideoLoaded).videos;
        emit(VideoError(e.toString(), currentVideos: currentVideos));
      } else {
        emit(VideoError(e.toString()));
      }
    }
  }

  Future<void> _onGenerateThumbnail(
      GenerateThumbnail event, Emitter<VideoState> emit) async {
    try {
      if (state is VideoLoaded) {
        final currentState = state as VideoLoaded;
        final updatedVideo =
            await videoRepository.generateThumbnail(event.video);

        final updatedVideos = currentState.videos.map((video) {
          return video.path == updatedVideo.path ? updatedVideo : video;
        }).toList();

        emit(VideoLoaded(
          videos: updatedVideos,
          hasReachedEnd: currentState.hasReachedEnd,
        ));
      }
    } catch (e) {
      // 썸네일 생성 실패는 무시하고 계속 진행
      print('Error generating thumbnail: $e');
    }
  }

  Future<void> _onAddVideo(AddVideo event, Emitter<VideoState> emit) async {
    try {
      if (state is VideoLoaded) {
        final currentState = state as VideoLoaded;
        emit(VideoLoading(
            currentVideos: currentState.videos, isFirstLoad: false));
      }

      await videoRepository.addVideo(event.path);
      _currentPage = 0;
      final videos = await videoRepository.getVideos(
          page: _currentPage, pageSize: _pageSize);
      final hasReachedEnd = videos.length < _pageSize;
      emit(VideoLoaded(videos: videos, hasReachedEnd: hasReachedEnd));
    } catch (e) {
      if (state is VideoLoaded) {
        final currentVideos = (state as VideoLoaded).videos;
        emit(VideoError(e.toString(), currentVideos: currentVideos));
      } else {
        emit(VideoError(e.toString()));
      }
    }
  }

  Future<void> _onDeleteVideo(
      DeleteVideo event, Emitter<VideoState> emit) async {
    try {
      if (state is VideoLoaded) {
        final currentState = state as VideoLoaded;
        emit(VideoLoading(
            currentVideos: currentState.videos, isFirstLoad: false));

        await videoRepository.deleteVideo(event.path);

        final videos = await videoRepository.getVideos(
            page: _currentPage, pageSize: _pageSize);
        final hasReachedEnd = videos.length < _pageSize;
        emit(VideoLoaded(videos: videos, hasReachedEnd: hasReachedEnd));
      }
    } catch (e) {
      if (state is VideoLoaded) {
        final currentVideos = (state as VideoLoaded).videos;
        emit(VideoError(e.toString(), currentVideos: currentVideos));
      } else {
        emit(VideoError(e.toString()));
      }
    }
  }
}
