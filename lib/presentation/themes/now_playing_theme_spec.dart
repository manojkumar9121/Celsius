import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/presentation/providers/settings_provider.dart';

/// Decorative background treatment used by a Now Playing theme.
enum BackgroundLayer {
  /// Plain solid/gradient background.
  none,

  /// Riso Zine: two radial-masked halftone dot patches.
  halftonePatches,

  /// Paper Press: seeded grain noise + vignette.
  paperGrain,

  /// Pocket LCD: dot-matrix pixel grid overlay.
  pixelGrid,

  /// Concrete: neutral grain + rotated outline watermark word.
  concreteGrain,

  /// Sumi Ink: washi fiber noise + faint enso ring.
  sumiWash,
}

/// How the album artwork is framed on the Now Playing screen.
enum ArtFrameStyle { classic, riso, paper, lcd, concrete, scroll }

/// Layout style for the bottom navigation strip.
enum NowPlayingNavStyle {
  /// Three boxed pills (default for all non-LCD themes).
  pill,

  /// Single thin LCD-bar strip — compact, dot-matrix labels with dot separators.
  lcdBar,
}

/// Complete visual skin for the Now Playing screen.
///
/// One spec per [NowPlayingTheme]. The [NowPlayingThemeSpec.classic] spec is
/// the original dark + dominant-color design and is the default; the rest
/// translate the HTML design prototypes (Qwen Set 2/3) 1:1.
class NowPlayingThemeSpec {
  final NowPlayingTheme id;
  final String label;
  final String description;

  // Background -------------------------------------------------------------

  /// Classic: blurred artwork behind a dark gradient. When false the
  /// [backgroundColor]/[backgroundGradient] replaces the artwork.
  final bool showBlurredArtwork;
  final Color? backgroundColor;
  final List<Color>? backgroundGradient;
  final BackgroundLayer backgroundLayer;

  final bool showLed;
  final bool showGlare;

  // Top bar ----------------------------------------------------------------

  final Color iconColor;
  final String? topLabel;
  final TextStyle topLabelStyle;

  // Info text --------------------------------------------------------------

  final TextStyle titleStyle;
  final TextStyle artistStyle;

  /// LCD only: animated "► PLAYING / ❚❚ PAUSED" line under the artist.
  final bool showPlayStatus;

  // Action pills -----------------------------------------------------------

  final Color pillTextColor;
  final Color pillBorderColor;
  final Color pillBackgroundColor;
  final double pillRadius;
  final double pillBorderWidth;
  final double pillBorderAlpha;
  final List<BoxShadow> pillShadows;
  final TextStyle? pillTextStyle;

  /// Heart icon color inside the Favorite pill; null keeps the classic
  /// dominant-color accent behavior.
  final Color? pillHeartColor;

  // Seek bar ---------------------------------------------------------------

  final Color seekActiveColor;
  final Color seekInactiveColor;
  final double seekTrackHeight;
  final BorderSide? seekTrackBorder;
  final bool seekStripedFill;

  /// Knob side length; null renders no knob (classic, LCD).
  final double? seekKnobSize;
  final double seekKnobRadius;
  final Color? seekKnobColor;
  final List<BoxShadow> seekKnobShadows;
  final TextStyle timeStyle;

  // Transport --------------------------------------------------------------

  final Color transportColor;

  /// Active-state color (shuffle/repeat on). Null uses the app theme's
  /// primary color — the classic behavior.
  final Color? transportActiveColor;
  final Color playBackgroundColor;
  final Color playForegroundColor;
  final double playSize;
  final double playIconSize;

  /// Null renders a circle; a value renders rounded rect (LCD) or square
  /// Square play button (Riso / Paper).
  final double? playRadius;
  final List<BoxShadow> playShadows;

  // Waveform ---------------------------------------------------------------

  /// Per-bar color cycle (Riso pink/blue, Paper brick).
  final List<Color>? waveformPalette;
  final Color waveformActiveColor;
  final Color waveformInactiveColor;
  final double waveformBarGap;
  final bool waveformSquareBars;

  /// LCD: vertical ink stripes inside each bar.
  final bool waveformStripes;

  // Bottom navigation ------------------------------------------------------

  final Color navTextColor;
  final Color navBackgroundColor;
  final Color navBorderColor;
  final double navRadius;
  final TextStyle navTextStyle;

  /// Bottom nav layout: boxed pills (default) or single thin LCD bar.
  final NowPlayingNavStyle navStyle;

  // Art frame --------------------------------------------------------------

  final ArtFrameStyle artFrame;

  const NowPlayingThemeSpec({
    required this.id,
    required this.label,
    required this.description,
    this.showBlurredArtwork = false,
    this.backgroundColor,
    this.backgroundGradient,
    this.backgroundLayer = BackgroundLayer.none,
    this.showLed = false,
    this.showGlare = false,
    this.iconColor = Colors.white,
    this.topLabel,
    this.topLabelStyle = const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2.2),
    required this.titleStyle,
    required this.artistStyle,
    this.showPlayStatus = false,
    required this.pillTextColor,
    required this.pillBorderColor,
    required this.pillBackgroundColor,
    this.pillRadius = 20,
    this.pillBorderWidth = 1,
    this.pillBorderAlpha = 0.3,
    this.pillShadows = const [],
    this.pillTextStyle,
    this.pillHeartColor,
    required this.seekActiveColor,
    required this.seekInactiveColor,
    this.seekTrackHeight = 2,
    this.seekTrackBorder,
    this.seekStripedFill = false,
    this.seekKnobSize,
    this.seekKnobRadius = 0,
    this.seekKnobColor,
    this.seekKnobShadows = const [],
    required this.timeStyle,
    required this.transportColor,
    this.transportActiveColor,
    required this.playBackgroundColor,
    required this.playForegroundColor,
    this.playSize = 68,
    this.playIconSize = 40,
    this.playRadius,
    this.playShadows = const [],
    this.waveformPalette,
    required this.waveformActiveColor,
    required this.waveformInactiveColor,
    this.waveformBarGap = 2,
    this.waveformSquareBars = false,
    this.waveformStripes = false,
    required this.navTextColor,
    required this.navBackgroundColor,
    required this.navBorderColor,
    this.navRadius = 12,
    required this.navTextStyle,
    this.navStyle = NowPlayingNavStyle.pill,
    required this.artFrame,
  });

  /// Primary foreground ink for this skin (the color its own title text is
  /// painted with). The auxiliary screens (queue, playlist, lyrics) reuse it
  /// so their text stays readable on the skin's background.
  Color get inkColor => titleStyle.color ?? Colors.white;

  /// Slider theme for themed skins; null keeps the classic inline defaults.
  SliderThemeData? sliderTheme() {
    if (id == NowPlayingTheme.classic) return null;
    return SliderThemeData(
      trackHeight: seekTrackHeight,
      activeTrackColor: seekActiveColor,
      inactiveTrackColor: seekInactiveColor,
      thumbColor: seekKnobColor,
      thumbShape: seekKnobSize == null
          ? const RoundSliderThumbShape(enabledThumbRadius: 0)
          : SquareSliderThumbShape(
              size: seekKnobSize!,
              radius: seekKnobRadius,
              color: seekKnobColor!,
              shadows: seekKnobShadows,
            ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
      overlayColor: Colors.transparent,
      trackShape: ThemedTrackShape(
        trackHeight: seekTrackHeight,
        activeColor: seekActiveColor,
        inactiveColor: seekInactiveColor,
        border: seekTrackBorder,
        striped: seekStripedFill,
      ),
    );
  }
}

/// Builds the active spec for the currently selected [NowPlayingTheme].
final nowPlayingThemeSpecProvider = Provider<NowPlayingThemeSpec>((ref) {
  final theme = ref.watch(settingsProvider.select((s) => s.nowPlayingTheme));
  return nowPlayingThemeSpecs[theme]!;
});

/// All specs indexed by [NowPlayingTheme].
final Map<NowPlayingTheme, NowPlayingThemeSpec> nowPlayingThemeSpecs = {
  NowPlayingTheme.classic: _classic,
  NowPlayingTheme.risoZine: _risoZine,
  NowPlayingTheme.paperPress: _paperPress,
  NowPlayingTheme.pocketLcd: _pocketLcd,
  NowPlayingTheme.concrete: _concrete,
  NowPlayingTheme.sumi: _sumi,
  NowPlayingTheme.concreteNoir: _concreteNoir,
  NowPlayingTheme.sumiNight: _sumiNight,
};

// ---------------------------------------------------------------------------
// Theme definitions (colors/geometry from the HTML design prototypes)
// ---------------------------------------------------------------------------

const Color _cream = Color(0xFFF5F1E8);
const Color _paperCream = Color(0xFFF2EFE6);

const NowPlayingThemeSpec _classic = NowPlayingThemeSpec(
  id: NowPlayingTheme.classic,
  label: 'Classic',
  description: 'Original design — blurred artwork with dominant color accents',
  showBlurredArtwork: true,
  titleStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
  artistStyle: TextStyle(fontSize: 15, color: Color(0x99FFFFFF)),
  pillTextColor: Color(0xB3FFFFFF),
  pillBorderColor: Color(0xB3FFFFFF),
  pillBackgroundColor: Color(0x40000000),
  pillRadius: 20,
  pillHeartColor: null,
  seekActiveColor: Colors.white,
  seekInactiveColor: Color(0x26FFFFFF),
  timeStyle: TextStyle(fontSize: 12, color: Colors.white),
  transportColor: Colors.white,
  transportActiveColor: null,
  playBackgroundColor: Colors.white,
  playForegroundColor: Colors.black,
  playSize: 68,
  playIconSize: 40,
  playShadows: [BoxShadow(color: Color(0x4DFFFFFF), blurRadius: 16)],
  waveformActiveColor: Colors.white,
  waveformInactiveColor: Color(0x4DFFFFFF),
  navTextColor: Colors.white,
  navBackgroundColor: Color(0x14FFFFFF),
  navBorderColor: Colors.transparent,
  navRadius: 12,
  navTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  artFrame: ArtFrameStyle.classic,
);

const NowPlayingThemeSpec _risoZine = NowPlayingThemeSpec(
  id: NowPlayingTheme.risoZine,
  label: 'Riso Zine',
  description: 'Two-ink risograph: fluoro pink + process blue on cream paper',
  backgroundColor: _cream,
  backgroundLayer: BackgroundLayer.halftonePatches,
  iconColor: Color(0xFF0078BF),
  topLabel: 'Now Playing',
  topLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2.2, color: Color(0xFFFF48B0)),
  titleStyle: TextStyle(
    fontSize: 24,
    fontFamily: 'ArchivoBlack',
    color: Color(0xFF16151A),
    shadows: [
      Shadow(color: Color(0xB3FF48B0), offset: Offset(2.5, 2)),
      Shadow(color: Color(0xB30078BF), offset: Offset(-2.5, -2)),
    ],
  ),
  artistStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: Color(0xFF5A5661)),
  pillTextColor: Color(0xFF0078BF),
  pillBorderColor: Color(0xFF0078BF),
  pillBackgroundColor: Color(0xFFFFFDF6),
  pillRadius: 10,
  pillBorderWidth: 2,
  pillBorderAlpha: 1,
  pillShadows: [BoxShadow(color: Color(0xFFFF48B0), offset: Offset(3, 3), blurRadius: 0)],
  pillHeartColor: Color(0xFFFF48B0),
  seekActiveColor: Color(0xFF0078BF),
  seekInactiveColor: Color(0x330078BF),
  seekTrackHeight: 5,
  seekKnobSize: 14,
  seekKnobRadius: 3,
  seekKnobColor: Color(0xFFFF48B0),
  seekKnobShadows: [BoxShadow(color: Color(0xFF0078BF), offset: Offset(2, 2), blurRadius: 0)],
  timeStyle: TextStyle(fontSize: 11.5, color: Color(0xFF5A5661)),
  transportColor: Color(0xFF16151A),
  transportActiveColor: Color(0xFFFF48B0),
  playBackgroundColor: Color(0xFF0078BF),
  playForegroundColor: Color(0xFFFFFDF6),
  playSize: 70,
  playIconSize: 30,
  playShadows: [BoxShadow(color: Color(0xFFFF48B0), offset: Offset(5, 5), blurRadius: 0)],
  waveformPalette: [Color(0xFFFF48B0), Color(0xFF0078BF)],
  waveformActiveColor: Color(0xFFFF48B0),
  waveformInactiveColor: Color(0x330078BF),
  waveformBarGap: 2.5,
  waveformSquareBars: true,
  navTextColor: Color(0xFF0078BF),
  navBackgroundColor: Color(0xFFFFFDF6),
  navBorderColor: Color(0xFF0078BF),
  navRadius: 10,
  navTextStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
  artFrame: ArtFrameStyle.riso,
);

const NowPlayingThemeSpec _paperPress = NowPlayingThemeSpec(
  id: NowPlayingTheme.paperPress,
  label: 'Paper Press',
  description: 'Light editorial — ink on cream paper, serif type, taped art',
  backgroundColor: _paperCream,
  backgroundLayer: BackgroundLayer.paperGrain,
  iconColor: Color(0xFF1C1A17),
  topLabel: 'Now Playing',
  topLabelStyle: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 2.4, color: Color(0xFF8A8378)),
  titleStyle: TextStyle(
    fontSize: 27,
    fontFamily: 'PlayfairDisplay',
    fontWeight: FontWeight.w700,
    color: Color(0xFF171512),
  ),
  artistStyle: TextStyle(fontSize: 12, letterSpacing: 2.2, color: Color(0xFF6F675C)),
  pillTextColor: Color(0xFF2A2620),
  pillBorderColor: Color(0x661C1A17),
  pillBackgroundColor: Colors.transparent,
  pillRadius: 6,
  pillBorderAlpha: 0.4,
  pillHeartColor: Color(0xFFC2452D),
  seekActiveColor: Color(0xFF1C1A17),
  seekInactiveColor: Color(0x2E1C1A17),
  seekTrackHeight: 4,
  seekKnobSize: 12,
  seekKnobRadius: 2,
  seekKnobColor: Color(0xFF1C1A17),
  timeStyle: TextStyle(fontSize: 11.5, color: Color(0xFF6F675C)),
  transportColor: Color(0xFF3A352D),
  transportActiveColor: Color(0xFFC2452D),
  playBackgroundColor: Color(0xFF171512),
  playForegroundColor: Color(0xFFF4F1E8),
  playSize: 70,
  playIconSize: 30,
  playShadows: [BoxShadow(color: Color(0x4D171512), offset: Offset(0, 10), blurRadius: 24)],
  waveformActiveColor: Color(0xFF22201B),
  waveformInactiveColor: Color(0x2E22201B),
  waveformBarGap: 2.5,
  waveformSquareBars: true,
  navTextColor: Color(0xFF2A2620),
  navBackgroundColor: Color(0x0A1C1A17),
  navBorderColor: Color(0x4D1C1A17),
  navRadius: 8,
  navTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  artFrame: ArtFrameStyle.paper,
);

const NowPlayingThemeSpec _pocketLcd = NowPlayingThemeSpec(
  id: NowPlayingTheme.pocketLcd,
  label: 'Pocket LCD',
  description: 'Handheld dot-matrix: olive LCD, pixel font',
  backgroundColor: Color(0xFF9BBC0F),
  backgroundGradient: [Color(0xFF9BBC0F), Color(0xFF8BAC0F)],
  backgroundLayer: BackgroundLayer.pixelGrid,
  showLed: true,
  showGlare: true,
  iconColor: Color(0xFF306230),
  topLabel: 'Dot Matrix Stereo',
  topLabelStyle: TextStyle(fontFamily: 'PressStart2P', fontSize: 8, letterSpacing: 1, color: Color(0xFF306230)),
  titleStyle: TextStyle(
    fontSize: 32,
    fontFamily: 'VT323',
    color: Color(0xFF0F380F),
    shadows: [Shadow(color: Color(0xFF306230), offset: Offset(2, 2))],
  ),
  artistStyle: TextStyle(fontSize: 19, fontFamily: 'VT323', color: Color(0xFF306230)),
  showPlayStatus: true,
  pillTextColor: Color(0xFF0F380F),
  pillBorderColor: Color(0xFF0F380F),
  pillBackgroundColor: Color(0x140F380F),
  pillRadius: 4,
  pillBorderWidth: 2,
  pillBorderAlpha: 1,
  pillTextStyle: TextStyle(fontFamily: 'PressStart2P', fontSize: 8),
  pillHeartColor: Color(0xFF8A2A3C),
  seekActiveColor: Color(0xFF0F380F),
  seekInactiveColor: Color(0x260F380F),
  seekTrackHeight: 12,
  seekTrackBorder: BorderSide(color: Color(0xFF0F380F), width: 2),
  seekStripedFill: true,
  timeStyle: TextStyle(fontSize: 15, fontFamily: 'VT323', color: Color(0xFF306230)),
  transportColor: Color(0xFF306230),
  transportActiveColor: Color(0xFF0F380F),
  playBackgroundColor: Color(0xFF0F380F),
  playForegroundColor: Color(0xFF9BBC0F),
  playSize: 70,
  playIconSize: 30,
  playRadius: 10,
  playShadows: [
    BoxShadow(color: Color(0xFF306230), offset: Offset(3, 3), blurRadius: 0),
    BoxShadow(color: Color(0xFF8BAC0F), spreadRadius: 3),
    BoxShadow(color: Color(0xFF306230), spreadRadius: 5),
  ],
  waveformActiveColor: Color(0xFF0F380F),
  waveformInactiveColor: Color(0x260F380F),
  waveformBarGap: 3,
  waveformSquareBars: true,
  waveformStripes: true,
  navTextColor: Color(0xFF0F380F),
  navBackgroundColor: Color(0x0F0F380F),
  navBorderColor: Color(0xFF306230),
  navRadius: 6,
    navTextStyle: TextStyle(fontFamily: 'PressStart2P', fontSize: 8),
    navStyle: NowPlayingNavStyle.lcdBar,
    artFrame: ArtFrameStyle.lcd,
);

// ---------------------------------------------------------------------------
// Concrete / Concrete Noir — neo-brutalist poster (light + dark siblings)
// ---------------------------------------------------------------------------

const Color _concreteBg = Color(0xFFE9E5DB);
const Color _concreteInk = Color(0xFF16140F);
const Color _concreteCard = Color(0xFFFBFAF6);
const Color _signalRed = Color(0xFFFF3D00);
const Color _noirBg = Color(0xFF17171A);
const Color _noirInk = Color(0xFFEDEAE2);
const Color _noirCard = Color(0xFF232327);

const NowPlayingThemeSpec _concrete = NowPlayingThemeSpec(
  id: NowPlayingTheme.concrete,
  label: 'Concrete',
  description: 'Neo-brutalist poster — bone paper, hard ink borders, signal red',
  backgroundColor: _concreteBg,
  backgroundLayer: BackgroundLayer.concreteGrain,
  iconColor: _concreteInk,
  topLabel: 'NOW PLAYING',
  topLabelStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    fontFamily: 'monospace',
    color: _concreteInk,
  ),
  titleStyle: TextStyle(
    fontSize: 30,
    fontFamily: 'ArchivoBlack',
    color: _concreteInk,
    height: 1.04,
  ),
  artistStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    color: Color(0xFF5C574B),
  ),
  pillTextColor: _concreteInk,
  pillBorderColor: _concreteInk,
  pillBackgroundColor: _concreteCard,
  pillRadius: 4,
  pillBorderWidth: 2,
  pillBorderAlpha: 1,
  pillShadows: [BoxShadow(color: _concreteInk, offset: Offset(4, 4), blurRadius: 0)],
  pillHeartColor: _signalRed,
  seekActiveColor: _signalRed,
  seekInactiveColor: Color(0x1416140F),
  seekTrackHeight: 12,
  seekTrackBorder: BorderSide(color: _concreteInk, width: 2),
  seekStripedFill: true,
  seekKnobSize: 18,
  seekKnobRadius: 2,
  seekKnobColor: _concreteInk,
  timeStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: _concreteInk),
  transportColor: _concreteInk,
  transportActiveColor: _signalRed,
  playBackgroundColor: _concreteInk,
  playForegroundColor: _concreteCard,
  playSize: 70,
  playIconSize: 28,
  playRadius: 6,
  playShadows: [BoxShadow(color: _signalRed, offset: Offset(5, 5), blurRadius: 0)],
  waveformPalette: [_concreteInk, _concreteInk, _signalRed],
  waveformActiveColor: _signalRed,
  waveformInactiveColor: Color(0x2416140F),
  waveformBarGap: 3,
  waveformSquareBars: true,
  navTextColor: _concreteInk,
  navBackgroundColor: _concreteCard,
  navBorderColor: _concreteInk,
  navRadius: 0,
  navTextStyle: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2),
  artFrame: ArtFrameStyle.concrete,
);

const NowPlayingThemeSpec _concreteNoir = NowPlayingThemeSpec(
  id: NowPlayingTheme.concreteNoir,
  label: 'Concrete Noir',
  description: 'Concrete after dark — charcoal slab, bone ink, same signal red',
  backgroundColor: _noirBg,
  backgroundLayer: BackgroundLayer.concreteGrain,
  iconColor: _noirInk,
  topLabel: 'NOW PLAYING',
  topLabelStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    fontFamily: 'monospace',
    color: _noirInk,
  ),
  titleStyle: TextStyle(
    fontSize: 30,
    fontFamily: 'ArchivoBlack',
    color: _noirInk,
    height: 1.04,
  ),
  artistStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    color: Color(0xFF9B968A),
  ),
  pillTextColor: _noirInk,
  pillBorderColor: _noirInk,
  pillBackgroundColor: _noirCard,
  pillRadius: 4,
  pillBorderWidth: 2,
  pillBorderAlpha: 1,
  pillShadows: [BoxShadow(color: _noirInk, offset: Offset(4, 4), blurRadius: 0)],
  pillHeartColor: _signalRed,
  seekActiveColor: _signalRed,
  seekInactiveColor: Color(0x14EDEAE2),
  seekTrackHeight: 12,
  seekTrackBorder: BorderSide(color: _noirInk, width: 2),
  seekStripedFill: true,
  seekKnobSize: 18,
  seekKnobRadius: 2,
  seekKnobColor: _noirInk,
  timeStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: _noirInk),
  transportColor: _noirInk,
  transportActiveColor: _signalRed,
  playBackgroundColor: _noirInk,
  playForegroundColor: _noirBg,
  playSize: 70,
  playIconSize: 28,
  playRadius: 6,
  playShadows: [BoxShadow(color: _signalRed, offset: Offset(5, 5), blurRadius: 0)],
  waveformPalette: [_noirInk, _noirInk, _signalRed],
  waveformActiveColor: _signalRed,
  waveformInactiveColor: Color(0x24EDEAE2),
  waveformBarGap: 3,
  waveformSquareBars: true,
  navTextColor: _noirInk,
  navBackgroundColor: _noirCard,
  navBorderColor: _noirInk,
  navRadius: 0,
  navTextStyle: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2),
  artFrame: ArtFrameStyle.concrete,
);

// ---------------------------------------------------------------------------
// Sumi Ink / Sumi Night — sumi-e brush on paper (light + dark siblings)
// ---------------------------------------------------------------------------

const Color _washi = Color(0xFFF5F1E4);
const Color _sumiInk = Color(0xFF211E19);
const Color _vermillion = Color(0xFFC93A2E);
const Color _sumiGray = Color(0xFF6D675C);
const Color _nightPaper = Color(0xFF1B1A16);
const Color _nightWash = Color(0xFFE8E2D2);
const Color _nightGray = Color(0xFF8F887A);

const NowPlayingThemeSpec _sumi = NowPlayingThemeSpec(
  id: NowPlayingTheme.sumi,
  label: 'Sumi Ink',
  description: 'Sumi-e brush on washi paper — hanging scroll, vermillion seal',
  backgroundColor: _washi,
  backgroundLayer: BackgroundLayer.sumiWash,
  iconColor: _sumiInk,
  topLabel: '再生中 · NOW PLAYING',
  topLabelStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 4,
    fontFamily: 'PlayfairDisplay',
    color: _sumiGray,
  ),
  titleStyle: TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.w700,
    fontFamily: 'PlayfairDisplay',
    color: _sumiInk,
  ),
  artistStyle: TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 3.2,
    color: _sumiGray,
  ),
  pillTextColor: _sumiInk,
  pillBorderColor: Color(0x66211E19),
  pillBackgroundColor: Colors.transparent,
  pillRadius: 20,
  pillBorderAlpha: 1,
  pillHeartColor: _vermillion,
  seekActiveColor: _sumiInk,
  seekInactiveColor: Color(0x38211E19),
  seekTrackHeight: 2,
  seekKnobSize: 14,
  seekKnobRadius: 7,
  seekKnobColor: _vermillion,
  timeStyle: TextStyle(fontSize: 11, letterSpacing: 1, color: _sumiGray),
  transportColor: _sumiInk,
  transportActiveColor: _vermillion,
  playBackgroundColor: Color(0xFFFBF8EF),
  playForegroundColor: _sumiInk,
  playSize: 74,
  playIconSize: 30,
  playShadows: [BoxShadow(color: Color(0x33211E19), offset: Offset(0, 8), blurRadius: 18)],
  waveformPalette: [_sumiInk, _sumiInk, _sumiInk, _vermillion],
  waveformActiveColor: _sumiInk,
  waveformInactiveColor: Color(0x2E211E19),
  waveformBarGap: 5,
  navTextColor: _sumiInk,
  navBackgroundColor: Colors.transparent,
  navBorderColor: Color(0x2E211E19),
  navRadius: 0,
  navTextStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: 'PlayfairDisplay', letterSpacing: 2),
  artFrame: ArtFrameStyle.scroll,
);

const NowPlayingThemeSpec _sumiNight = NowPlayingThemeSpec(
  id: NowPlayingTheme.sumiNight,
  label: 'Sumi Night',
  description: 'Sumi-e by night — charcoal paper, pale wash ink, live vermillion',
  backgroundColor: _nightPaper,
  backgroundLayer: BackgroundLayer.sumiWash,
  iconColor: _nightWash,
  topLabel: '再生中 · NOW PLAYING',
  topLabelStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 4,
    fontFamily: 'PlayfairDisplay',
    color: _nightGray,
  ),
  titleStyle: TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.w700,
    fontFamily: 'PlayfairDisplay',
    color: _nightWash,
  ),
  artistStyle: TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 3.2,
    color: _nightGray,
  ),
  pillTextColor: _nightWash,
  pillBorderColor: Color(0x59E8E2D2),
  pillBackgroundColor: Colors.transparent,
  pillRadius: 20,
  pillBorderAlpha: 1,
  pillHeartColor: _vermillion,
  seekActiveColor: _nightWash,
  seekInactiveColor: Color(0x38E8E2D2),
  seekTrackHeight: 2,
  seekKnobSize: 14,
  seekKnobRadius: 7,
  seekKnobColor: _vermillion,
  timeStyle: TextStyle(fontSize: 11, letterSpacing: 1, color: _nightGray),
  transportColor: _nightWash,
  transportActiveColor: _vermillion,
  playBackgroundColor: Color(0xFF26251F),
  playForegroundColor: _nightWash,
  playSize: 74,
  playIconSize: 30,
  playShadows: [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 8), blurRadius: 20)],
  waveformPalette: [_nightWash, _nightWash, _nightWash, _vermillion],
  waveformActiveColor: _nightWash,
  waveformInactiveColor: Color(0x2EE8E2D2),
  waveformBarGap: 5,
  navTextColor: _nightWash,
  navBackgroundColor: Colors.transparent,
  navBorderColor: Color(0x33E8E2D2),
  navRadius: 0,
  navTextStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: 'PlayfairDisplay', letterSpacing: 2),
  artFrame: ArtFrameStyle.scroll,
);

// ===========================================================================
// Slider shapes
// ===========================================================================

/// Square knob with hard offset shadows (Riso / Paper).
class SquareSliderThumbShape extends SliderComponentShape {
  final double size;
  final double radius;
  final Color color;
  final List<BoxShadow> shadows;

  const SquareSliderThumbShape({
    required this.size,
    required this.radius,
    required this.color,
    this.shadows = const [],
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(
      center: center,
      width: size,
      height: size,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    for (final shadow in shadows) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(shadow.offset),
          Radius.circular(radius),
        ),
        Paint()..color = shadow.color,
      );
    }
    canvas.drawRRect(rrect, Paint()..color = color);
  }
}

/// Track with optional border and striped active fill (LCD).
class ThemedTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final double trackHeight;
  final Color activeColor;
  final Color inactiveColor;
  final BorderSide? border;
  final bool striped;

  const ThemedTrackShape({
    required this.trackHeight,
    required this.activeColor,
    required this.inactiveColor,
    this.border,
    this.striped = false,
  });

  @override
  bool get isRounded => false;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.width <= 0 || trackRect.height <= 0) return;

    final ltr = textDirection == TextDirection.ltr;
    final activeRect = ltr
        ? Rect.fromLTRB(
            trackRect.left, trackRect.top, thumbCenter.dx, trackRect.bottom)
        : Rect.fromLTRB(
            thumbCenter.dx, trackRect.top, trackRect.right, trackRect.bottom);
    final inactiveRect = ltr
        ? Rect.fromLTRB(
            thumbCenter.dx, trackRect.top, trackRect.right, trackRect.bottom)
        : Rect.fromLTRB(
            trackRect.left, trackRect.top, thumbCenter.dx, trackRect.bottom);

    final borderWidth = border?.width ?? 0;
    final fillRect = trackRect.deflate(borderWidth / 2);

    if (striped && activeRect.width > 0) {
      canvas.save();
      canvas.clipRect(activeRect);
      canvas.drawRect(
        fillRect,
        Paint()..shader = _stripeShader(fillRect, activeColor),
      );
      canvas.restore();
    } else if (activeRect.width > 0) {
      canvas.drawRect(fillRect, Paint()..color = activeColor);
    }

    if (inactiveRect.width > 0) {
      canvas.save();
      canvas.clipRect(inactiveRect);
      canvas.drawRect(fillRect, Paint()..color = inactiveColor);
      canvas.restore();
    }

    if (border != null) {
      canvas.drawRect(
        fillRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = border!.color,
      );
    }
  }

  /// Vertical ink stripes: 3px ink / 2px gap (from the prototype).
  static Shader _stripeShader(Rect rect, Color ink) {
    const on = 3.0;
    const off = 2.0;
    final colors = <Color>[];
    final stops = <double>[];
    double t = 0;
    while (t < 1.0 - 1e-6) {
      final onEnd = min(t + on / rect.height, 1.0);
      colors
        ..add(ink)
        ..add(ink)
        ..add(Colors.transparent)
        ..add(Colors.transparent);
      stops
        ..add(t)
        ..add(onEnd)
        ..add(onEnd)
        ..add(min(onEnd + off / rect.height, 1.0));
      if (onEnd >= 1.0) break;
      t = onEnd + off / rect.height;
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(rect);
  }
}
