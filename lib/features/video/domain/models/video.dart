import 'package:equatable/equatable.dart';

class Video {
  final String id;
  final String path;
  final String? thumbnailPath;
  final Duration duration;
  final DateTime dateAdded;
  final int size;
  final bool isThumbnailGenerated;

  Video({
    required this.id,
    required this.path,
    this.thumbnailPath,
    required this.duration,
    required this.dateAdded,
    required this.size,
    this.isThumbnailGenerated = false,
  });

  Video copyWith({
    String? id,
    String? path,
    String? thumbnailPath,
    Duration? duration,
    DateTime? dateAdded,
    int? size,
    bool? isThumbnailGenerated,
  }) {
    return Video(
      id: id ?? this.id,
      path: path ?? this.path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      dateAdded: dateAdded ?? this.dateAdded,
      size: size ?? this.size,
      isThumbnailGenerated: isThumbnailGenerated ?? this.isThumbnailGenerated,
    );
  }
}
