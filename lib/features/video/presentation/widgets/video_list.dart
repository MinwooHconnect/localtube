import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/models/video.dart';
import '../bloc/video_bloc.dart';
import '../bloc/video_event.dart';
import '../bloc/video_state.dart';
import 'video_player_page.dart';

class VideoList extends StatefulWidget {
  final List<Video> videos;

  const VideoList({
    super.key,
    required this.videos,
  });

  @override
  State<VideoList> createState() => _VideoListState();
}

class _VideoListState extends State<VideoList> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _visibleVideoKeys = {};
  final Set<String> _thumbnailRequested = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibleItems();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<VideoBloc>().add(LoadMoreVideos());
    }
    _checkVisibleItems();
  }

  void _checkVisibleItems() {
    if (!_scrollController.hasClients) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final viewportHeight = renderBox.size.height;
    final scrollOffset = _scrollController.offset;
    final itemHeight = 200.0;

    final firstVisibleIndex = (scrollOffset / itemHeight).floor();
    final lastVisibleIndex =
        ((scrollOffset + viewportHeight) / itemHeight).ceil();

    // 현재 보이는 항목의 앞뒤로 여유를 두어 미리 로드
    final preloadCount = 2;
    final startIndex =
        (firstVisibleIndex - preloadCount).clamp(0, widget.videos.length);
    final endIndex =
        (lastVisibleIndex + preloadCount).clamp(0, widget.videos.length);

    final visibleRange = List.generate(
      endIndex - startIndex,
      (i) => i + startIndex,
    );

    final newVisibleKeys = <String>{};
    for (final index in visibleRange) {
      if (index >= 0 && index < widget.videos.length) {
        final video = widget.videos[index];
        newVisibleKeys.add(video.path);

        // 썸네일 생성 요청
        if (!video.isThumbnailGenerated &&
            !_thumbnailRequested.contains(video.path)) {
          _thumbnailRequested.add(video.path);

          // 각 비디오마다 100ms 간격으로 썸네일 생성 요청
          Future.delayed(
            Duration(milliseconds: (index - startIndex) * 100),
            () {
              if (mounted) {
                context.read<VideoBloc>().add(GenerateThumbnail(video));
                print('Requesting thumbnail for: ${video.path}');
              }
            },
          );
        }
      }
    }

    setState(() {
      _visibleVideoKeys.clear();
      _visibleVideoKeys.addAll(newVisibleKeys);
    });

    // 화면에서 벗어난 항목의 썸네일 요청 상태 제거
    _thumbnailRequested.removeWhere(
      (path) => !newVisibleKeys.contains(path),
    );
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) {
      return const Center(
        child: Text(
          'No videos found.\nMake sure you have granted storage permission.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification ||
            notification is UserScrollNotification) {
          _checkVisibleItems();
        }
        return true;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: widget.videos.length + 1,
        itemBuilder: (context, index) {
          if (index == widget.videos.length) {
            return BlocBuilder<VideoBloc, VideoState>(
              builder: (context, state) {
                if (state is VideoLoaded && state.hasReachedEnd) {
                  return const SizedBox();
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              },
            );
          }

          final video = widget.videos[index];
          return Dismissible(
            key: Key(video.path),
            onDismissed: (direction) {
              context.read<VideoBloc>().add(DeleteVideo(video.path));
            },
            background: Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoPlayerPage(video: video),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: !video.isThumbnailGenerated ||
                              video.thumbnailPath == null
                          ? Container(
                              color: Colors.grey[300],
                              child: const Icon(
                                Icons.video_library,
                                size: 48,
                              ),
                            )
                          : Image.file(
                              File(video.thumbnailPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red,
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        video.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
