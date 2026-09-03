import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:celsuis/core/constants/app_constants.dart';
import 'package:celsuis/core/widgets/custom_page_transition.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/presentation/providers/settings_provider.dart';
import 'package:celsuis/presentation/screens/home/home_screen.dart';
import 'package:celsuis/presentation/screens/library/library_screen.dart';
import 'package:celsuis/presentation/screens/settings/settings_screen.dart';
import 'package:celsuis/presentation/screens/now_playing/now_playing_screen.dart';
import 'package:celsuis/presentation/screens/now_playing/queue_screen.dart';
import 'package:celsuis/presentation/screens/now_playing/playlist_screen.dart';
import 'package:celsuis/presentation/screens/now_playing/lyrics_screen.dart';
import 'package:celsuis/presentation/screens/stats/stats_screen.dart';
import 'package:celsuis/presentation/screens/playlist/playlist_detail_screen.dart';
import 'package:celsuis/presentation/widgets/mini_player.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return MainScaffold(location: state.uri.toString(), child: child);
        },
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/library', builder: (context, state) => const LibraryScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/now-playing',
        pageBuilder: (context, state) => TransitionPage(
          key: state.pageKey,
          child: const NowPlayingScreen(),
          slideUp: true,
        ),
      ),
      GoRoute(
        path: '/queue',
        pageBuilder: (context, state) => TransitionPage(
          key: state.pageKey,
          child: const QueueScreen(),
          slideUp: false,
        ),
      ),
      GoRoute(
        path: '/playlist',
        pageBuilder: (context, state) => TransitionPage(
          key: state.pageKey,
          child: const PlaylistScreen(),
          slideUp: false,
        ),
      ),
      GoRoute(
        path: '/lyrics',
        pageBuilder: (context, state) => TransitionPage(
          key: state.pageKey,
          child: const LyricsScreen(),
          slideUp: false,
        ),
      ),
      GoRoute(
        path: '/stats',
        pageBuilder: (context, state) => TransitionPage(
          key: state.pageKey,
          child: const StatsScreen(),
          slideUp: false,
        ),
      ),
      GoRoute(
        path: '/playlist/:id',
        pageBuilder: (context, state) => TransitionPage(
          key: state.pageKey,
          child: PlaylistDetailScreen(playlistId: state.pathParameters['id']!),
          slideUp: false,
        ),
      ),
    ],
  );
});

class CelsuisApp extends ConsumerWidget {
  const CelsuisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final currentTheme = ref.watch(currentThemeProvider);
    final preset = ref.watch(settingsProvider.select((s) => s.themePreset));
    final effectiveLightTheme = currentTheme.brightness == Brightness.dark
        ? _lightFallbackTheme
        : _applyPocketLcdFonts(currentTheme, preset);
    final effectiveDarkTheme = currentTheme.brightness == Brightness.light
        ? _darkFallbackTheme
        : _applyPocketLcdFonts(currentTheme, preset);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: effectiveLightTheme,
      darkTheme: effectiveDarkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }

  static ThemeData _applyPocketLcdFonts(ThemeData theme, ThemePreset preset) {
    if (preset != ThemePreset.pocketLcd) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        displayLarge: theme.textTheme.displayLarge?.copyWith(fontFamily: 'VT323'),
        displayMedium: theme.textTheme.displayMedium?.copyWith(fontFamily: 'VT323'),
        displaySmall: theme.textTheme.displaySmall?.copyWith(fontFamily: 'VT323'),
        headlineLarge: theme.textTheme.headlineLarge?.copyWith(fontFamily: 'VT323'),
        headlineMedium: theme.textTheme.headlineMedium?.copyWith(fontFamily: 'VT323'),
        headlineSmall: theme.textTheme.headlineSmall?.copyWith(fontFamily: 'VT323'),
        titleLarge: theme.textTheme.titleLarge?.copyWith(fontFamily: 'PressStart2P'),
        titleMedium: theme.textTheme.titleMedium?.copyWith(fontFamily: 'PressStart2P'),
        titleSmall: theme.textTheme.titleSmall?.copyWith(fontFamily: 'PressStart2P'),
        bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'VT323'),
        bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'VT323'),
        bodySmall: theme.textTheme.bodySmall?.copyWith(fontFamily: 'VT323'),
        labelLarge: theme.textTheme.labelLarge?.copyWith(fontFamily: 'PressStart2P'),
        labelMedium: theme.textTheme.labelMedium?.copyWith(fontFamily: 'PressStart2P'),
        labelSmall: theme.textTheme.labelSmall?.copyWith(fontFamily: 'PressStart2P'),
      ),
    );
  }
}

class MainScaffold extends ConsumerWidget {
  final Widget child;
  final String location;
  const MainScaffold({required this.child, required this.location, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int currentIndex = 0;
    if (location == '/library') {
      currentIndex = 1;
    } else if (location == '/settings') {
      currentIndex = 2;
    }

    final navBar = NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/home');
            break;
          case 1:
            context.go('/library');
            break;
          case 2:
            context.go('/settings');
            break;
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
    final bottomBar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MiniPlayer(),
        navBar,
      ],
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          child,
        ],
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

final _lightFallbackTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(primary: Color(0xFF1DB954)),
  scaffoldBackgroundColor: const Color(0xFFF5F5F5),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFFF5F5F5)),
  cardTheme: const CardThemeData(color: Color(0xFFFFFFFF)),
);

final _darkFallbackTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(primary: Color(0xFF1DB954)),
  scaffoldBackgroundColor: const Color(0xFF121212),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF121212)),
  cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
);
