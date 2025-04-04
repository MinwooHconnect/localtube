import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:localtube/features/video/presentation/pages/home_page.dart';
import 'package:localtube/core/theme/app_theme.dart';
import 'package:localtube/features/video/domain/repositories/video_repository.dart';
import 'package:localtube/features/video/data/repositories/video_repository_impl.dart';
import 'package:localtube/features/video/presentation/bloc/video_bloc.dart';

final getIt = GetIt.instance;

void setupDependencies() {
  // Repositories
  getIt.registerLazySingleton<VideoRepository>(
    () => VideoRepositoryImpl(),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => VideoBloc(
            videoRepository: getIt<VideoRepository>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'LocalTube',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const HomePage(),
      ),
    );
  }
}
