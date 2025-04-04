import 'package:equatable/equatable.dart';
import '../../domain/models/video.dart';

abstract class VideoEvent extends Equatable {
  const VideoEvent();

  @override
  List<Object?> get props => [];
}

class LoadVideos extends VideoEvent {}

class LoadMoreVideos extends VideoEvent {}

class AddVideo extends VideoEvent {
  final String path;

  const AddVideo(this.path);

  @override
  List<Object?> get props => [path];
}

class DeleteVideo extends VideoEvent {
  final String path;

  const DeleteVideo(this.path);

  @override
  List<Object?> get props => [path];
}

class GenerateThumbnail extends VideoEvent {
  final Video video;

  const GenerateThumbnail(this.video);

  @override
  List<Object?> get props => [video];
}
