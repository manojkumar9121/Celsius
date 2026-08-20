import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:celsuis/core/widgets/cached_song_image.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/presentation/themes/now_playing_theme_spec.dart';

// ===========================================================================
// Background
// ===========================================================================

/// Renders the Now Playing screen background for a theme spec.
///
/// The [NowPlayingThemeSpec.classic] spec reproduces the original blurred
/// artwork + dark gradient exactly; the themed specs render their solid /
/// gradient base plus decorative painter layers (halftone patches, grain,
/// pixel grid), LCD glare and a blinking LED.
class NowPlayingBackground extends StatefulWidget {
  final NowPlayingThemeSpec spec;
  final SongEntity song;
  final Color avgColor;

  const NowPlayingBackground({
    super.key,
    required this.spec,
    required this.song,
    required this.avgColor,
  });

  @override
  State<NowPlayingBackground> createState() => _NowPlayingBackgroundState();
}

class _NowPlayingBackgroundState extends State<NowPlayingBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _ledController;

  @override
  void initState() {
    super.initState();
    if (widget.spec.showLed) {
      _ledController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant NowPlayingBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spec.showLed && _ledController == null) {
      _ledController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )..repeat();
    } else if (!widget.spec.showLed && _ledController != null) {
      _ledController?.dispose();
      _ledController = null;
    }
  }

  @override
  void dispose() {
    _ledController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final hasArt = widget.song.coverArtPath != null &&
        widget.song.coverArtPath!.isNotEmpty &&
        File(widget.song.coverArtPath!).existsSync();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (spec.showBlurredArtwork)
          // Classic: blurred artwork + dark gradient (unchanged).
          Stack(
            fit: StackFit.expand,
            children: [
              if (hasArt)
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Image.file(
                    File(widget.song.coverArtPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: widget.avgColor),
                  ),
                )
              else
                Container(color: widget.avgColor),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x80000000),
                      Color(0xA6000000),
                      Color(0xD9000000),
                      Colors.black,
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              ),
            ],
          )
        else ...[
          // Themed: solid or gradient base.
          Container(
            decoration: BoxDecoration(
              color: spec.backgroundColor,
              gradient: spec.backgroundGradient != null
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: spec.backgroundGradient!,
                    )
                  : null,
            ),
          ),
          // Decorative painter layers.
          switch (spec.backgroundLayer) {
            BackgroundLayer.halftonePatches => const CustomPaint(
                painter: HalftonePatchesPainter(),
              ),
            BackgroundLayer.paperGrain => const CustomPaint(
                painter: PaperGrainPainter(),
              ),
            BackgroundLayer.pixelGrid => const CustomPaint(
                painter: PixelGridPainter(ink: Color(0xFF0F380F)),
              ),
            BackgroundLayer.none => const SizedBox.shrink(),
          },
          // LCD diagonal glare band.
          if (spec.showGlare)
            const CustomPaint(painter: GlarePainter()),
          // LCD blinking power LED.
          if (spec.showLed && _ledController != null)
            Positioned(
              top: 76,
              left: 32,
              child: AnimatedBuilder(
                animation: _ledController!,
                builder: (context, _) {
                  final v = _ledController!.value;
                  final on = v < 0.7;
                  return Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD43A3A).withValues(alpha: on ? 1 : 0.25),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFD43A3A).withValues(alpha: on ? 0.9 : 0.2),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  );
                },
),
          ),
        ],
      ],
    );
  }
}

/// Riso Zine: two radial-masked halftone dot patches (blue top-right,
/// pink bottom-left), sized for a phone screen.
class HalftonePatchesPainter extends CustomPainter {
  const HalftonePatchesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _paintPatch(canvas, size,
        center: Offset(size.width + 60, -40),
        radius: 240,
        dotColor: const Color(0xFF0078BF),
        spacing: 8,
        alpha: 0.55);
    _paintPatch(canvas, size,
        center: Offset(-40, size.height - 160),
        radius: 240,
        dotColor: const Color(0xFFFF48B0),
        spacing: 8,
        alpha: 0.55);
  }

  void _paintPatch(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double radius,
    required Color dotColor,
    required double spacing,
    required double alpha,
  }) {
    final paint = Paint()..color = dotColor;
    final startX = (center.dx - radius).floorToDouble();
    final endX = (center.dx + radius).ceilToDouble();
    final startY = (center.dy - radius).floorToDouble();
    final endY = (center.dy + radius).ceilToDouble();
    for (double y = startY; y <= endY; y += spacing) {
      for (double x = startX; x <= endX; x += spacing) {
        final d = (Offset(x, y) - center).distance;
        if (d > radius) continue;
        final falloff = (1 - d / radius).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset(x, y),
          0.9,
          paint..color = dotColor.withValues(alpha: alpha * falloff * falloff),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant HalftonePatchesPainter oldDelegate) => false;
}

/// Paper Press: seeded grain noise + warm vignette.
class PaperGrainPainter extends CustomPainter {
  const PaperGrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final dot = Paint();
    for (int i = 0; i < 1800; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      dot.color = Colors.black.withValues(alpha: 0.02 + rng.nextDouble() * 0.03);
      canvas.drawCircle(Offset(x, y), 0.6 + rng.nextDouble() * 0.5, dot);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.9,
          colors: [Colors.transparent, Color(0x24D2C6AE)],
          stops: [0.6, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant PaperGrainPainter oldDelegate) => false;
}

/// Pocket LCD: dot-matrix grid of faint ink lines.
class PixelGridPainter extends CustomPainter {
  final Color ink;

  const PixelGridPainter({required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final v = Paint()
      ..color = ink.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    final h = Paint()
      ..color = ink.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), v);
    }
    for (double y = 0; y <= size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), h);
    }
  }

  @override
  bool shouldRepaint(covariant PixelGridPainter oldDelegate) =>
      oldDelegate.ink != ink;
}

/// Pocket LCD: diagonal glare band across the screen.
class GlarePainter extends CustomPainter {
  const GlarePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.transparent,
        Color(0x24FFFFF0),
        Color(0x0DFFFFF0),
        Colors.transparent,
      ],
      stops: [0.42, 0.46, 0.54, 0.58],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant GlarePainter oldDelegate) => false;
}

// ===========================================================================
// Art frame
// ===========================================================================

/// Wraps the album artwork in the theme's frame treatment.
///
/// Frames translate the HTML prototypes: classic keeps the rounded card,
/// Riso adds a hard pink shadow + halftone duotone overlay + star badge,
/// Paper adds tape corners + caption, LCD adds the pixel bezel + track label,
/// Riso adds a halftone duotone; Paper tape corners; LCD a pixel bezel.
class NowPlayingArtFrame extends StatelessWidget {
  final NowPlayingThemeSpec spec;
  final SongEntity song;
  final double size;
  final int? queueIndex;

  const NowPlayingArtFrame({
    super.key,
    required this.spec,
    required this.song,
    required this.size,
    this.queueIndex,
  });

  bool get _hasArt =>
      song.coverArtPath != null &&
      song.coverArtPath!.isNotEmpty &&
      File(song.coverArtPath!).existsSync();

  @override
  Widget build(BuildContext context) {
    switch (spec.artFrame) {
      case ArtFrameStyle.classic:
        return _classicFrame();
      case ArtFrameStyle.riso:
        return _risoFrame();
      case ArtFrameStyle.paper:
        return _paperFrame();
      case ArtFrameStyle.lcd:
        return _lcdFrame();
    }
  }

  Widget _artContent() {
    if (_hasArt) {
      return Image.file(
        File(song.coverArtPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final color = hashToColor(song.id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.5)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.3,
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
  }

  // Classic: rounded card, soft shadow, ClipRRect (unchanged).
  Widget _classicFrame() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _artContent(),
      ),
    );
  }

  // Riso Zine: cream card, blue rule, hard pink shadow, halftone overlay,
  // "33⅓" star badge.
  Widget _risoFrame() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF6),
            border: Border.all(color: const Color(0xFF0078BF), width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFFF48B0),
                offset: Offset(6, 6),
                blurRadius: 0,
              ),
            ],
          ),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _artContent(),
                const CustomPaint(painter: ArtHalftonePainter()),
              ],
            ),
          ),
        ),
        Positioned(
          top: -24,
          right: -26,
          child: _StarBadge(label: '33 1/3', size: 82),
        ),
      ],
    );
  }

  // Paper Press: ink frame on cream, tape corners, caption below.
  Widget _paperFrame() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x591C1A17)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFE9DB),
                  border: Border.all(color: const Color(0xFF22201B), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E3C3426),
                      offset: Offset(0, 14),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: ClipRect(child: _artContent()),
              ),
              _tape(top: -12, left: -24, angle: -45),
              _tape(top: -12, right: -24, angle: 45),
              _tape(bottom: -12, left: -24, angle: 45),
              _tape(bottom: -12, right: -24, angle: -45),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'fig. 01 — ${song.title.toLowerCase()} · 33⅓ rpm',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: 2.4,
            color: Color(0xFF8A8378),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _tape({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double angle,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Transform.rotate(
        angle: angle * pi / 180,
        child: Container(
          width: 66,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xD9D5D4B2),
            boxShadow: const [
              BoxShadow(color: Color(0x2E000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  // Pocket LCD: dark-green pixel bezel + rings, scanline bg, track label.
  Widget _lcdFrame() {
    final index = queueIndex ?? 1;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF8BAC0F),
            border: Border.all(color: const Color(0xFF0F380F), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xFF8BAC0F), spreadRadius: 3),
              BoxShadow(color: Color(0xFF306230), spreadRadius: 6),
            ],
          ),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _artContent(),
                const CustomPaint(
                  painter: PixelGridPainter(ink: Color(0xFF0F380F)),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 6,
          child: Text(
            'TRACK ${(index + 1).toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 8,
              color: Color(0xFF306230),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pink halftone duotone dots over the Riso artwork.
class ArtHalftonePainter extends CustomPainter {
  const ArtHalftonePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFF48B0);
    const spacing = 7.0;
    for (double y = 0; y <= size.height; y += spacing) {
      for (double x = 0; x <= size.width; x += spacing) {
        final d = (Offset(x, y) - size.center(Offset.zero)).distance /
            (size.shortestSide / 2);
        if (d > 1) continue;
        canvas.drawCircle(
          Offset(x, y),
          1.0,
          paint..color = const Color(0xFFFF48B0).withValues(alpha: 0.28 * (1 - d)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ArtHalftonePainter oldDelegate) => false;
}

/// Pink star badge ("33 1/3") — 24-point star polygon from the prototype.
class _StarBadge extends StatelessWidget {
  final String label;
  final double size;

  const _StarBadge({required this.label, required this.size});

  static final List<Offset> _points = [
    (50, 0), (61, 12), (76, 6), (79, 22), (95, 24), (88, 38),
    (100, 50), (88, 62), (95, 76), (79, 78), (76, 94), (61, 88),
    (50, 100), (39, 88), (24, 94), (21, 78), (5, 76), (12, 62),
    (0, 50), (12, 38), (5, 24), (21, 22), (24, 6), (39, 12),
  ].map((p) => Offset(p.$1 / 100, p.$2 / 100)).toList();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 12 * pi / 180,
      child: ClipPath(
        clipper: _StarClipper(size),
        child: Container(
          width: size,
          height: size,
          color: const Color(0xFFFF48B0),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: -12 * pi / 180,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'ArchivoBlack',
                fontSize: 15,
                color: Color(0xFFFFFDF6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarClipper extends CustomClipper<Path> {
  final double size;

  const _StarClipper(this.size);

  @override
  Path getClip(Size _) {
    final path = Path();
    for (var i = 0; i < _StarBadge._points.length; i++) {
      final p = _StarBadge._points[i];
      final point = Offset(p.dx * size, p.dy * size);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _StarClipper oldClipper) => oldClipper.size != size;
}

// ===========================================================================
// LCD play status line
// ===========================================================================

/// Pocket LCD: blinking "PLAYING / PAUSED" line under the artist.
class LcdStatusLine extends StatefulWidget {
  final bool playing;

  const LcdStatusLine({super.key, required this.playing});

  @override
  State<LcdStatusLine> createState() => _LcdStatusLineState();
}

class _LcdStatusLineState extends State<LcdStatusLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        final visible = !widget.playing || _blink.value < 0.5;
        return Text(
          widget.playing ? 'PLAYING' : 'PAUSED',
          style: TextStyle(
            fontFamily: 'VT323',
            fontSize: 18,
            color: const Color(0xFF0F380F).withValues(alpha: visible ? 1 : 0.55),
          ),
        );
      },
    );
  }
}
