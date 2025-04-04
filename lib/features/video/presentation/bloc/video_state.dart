import 'package:equatable/equatable.dart';
import '../../domain/models/video.dart';

abstract class VideoState extends Equatable {
  const VideoState();

  @override
  List<Object?> get props => [];
}

class VideoInitial extends VideoState {}

class VideoLoading extends VideoState {
  final List<Video> currentVideos;
  final bool isFirstLoad;

  const VideoLoading({
    this.currentVideos = const [],
    this.isFirstLoad = true,
  });

  @override
  List<Object?> get props => [currentVideos, isFirstLoad];
}

class VideoLoaded extends VideoState {
  final List<Video> videos;
  final bool hasReachedEnd;

  const VideoLoaded({
    required this.videos,
    this.hasReachedEnd = false,
  });

  @override
  List<Object?> get props => [videos, hasReachedEnd];

  VideoLoaded copyWith({
    List<Video>? videos,
    bool? hasReachedEnd,
  }) {
    return VideoLoaded(
      videos: videos ?? this.videos,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
    );
  }
}

class VideoError extends VideoState {
  final String message;
  final List<Video> currentVideos;

  const VideoError(this.message, {this.currentVideos = const []});

  @override
  List<Object?> get props => [message, currentVideos];
}
