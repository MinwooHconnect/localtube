import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/video_bloc.dart';
import '../bloc/video_event.dart';
import '../bloc/video_state.dart';
import '../widgets/video_list.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalTube'),
      ),
      body: BlocBuilder<VideoBloc, VideoState>(
        builder: (context, state) {
          if (state is VideoInitial) {
            context.read<VideoBloc>().add(LoadVideos());
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('로컬 비디오를 검색하는 중...'),
                ],
              ),
            );
          }

          if (state is VideoLoading) {
            if (state.isFirstLoad) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('비디오 썸네일을 생성하는 중...'),
                  ],
                ),
              );
            }
            return VideoList(videos: state.currentVideos);
          }

          if (state is VideoLoaded) {
            return VideoList(videos: state.videos);
          }

          if (state is VideoError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(state.message),
                  if (state.currentVideos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    VideoList(videos: state.currentVideos),
                  ],
                ],
              ),
            );
          }

          return const SizedBox();
        },
      ),
    );
  }
}
