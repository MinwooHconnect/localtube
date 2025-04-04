import 'package:equatable/equatable.dart';

class Video extends Equatable {
  final String path;
  final String title;
  final DateTime dateAdded;
  final String? thumbnailPath;
  final bool isThumbnailGenerated;

  const Video({
    required this.path,
    required this.title,
    required this.dateAdded,
    this.thumbnailPath,
    this.isThumbnailGenerated = false,
  });

  Video copyWith({
    String? path,
    String? title,
    DateTime? dateAdded,
    String? thumbnailPath,
    bool? isThumbnailGenerated,
  }) {
    return Video(
      path: path ?? this.path,
      title: title ?? this.title,
      dateAdded: dateAdded ?? this.dateAdded,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isThumbnailGenerated: isThumbnailGenerated ?? this.isThumbnailGenerated,
    );
  }

  @override
  List<Object?> get props =>
      [path, title, dateAdded, thumbnailPath, isThumbnailGenerated];
}
