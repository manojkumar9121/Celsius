import 'dart:io';
import 'package:flutter/material.dart';

class SongCoverImage extends StatefulWidget {
  final String? coverArtPath;
  final double? width;
  final double? height;
  final double borderRadius;
  final Widget Function(BuildContext, double, double) placeholderBuilder;

  const SongCoverImage({
    super.key,
    this.coverArtPath,
    this.width,
    this.height,
    this.borderRadius = 6,
    required this.placeholderBuilder,
  });

  @override
  State<SongCoverImage> createState() => _SongCoverImageState();
}

class _SongCoverImageState extends State<SongCoverImage> {
  bool _hasFile = false;
  File? _file;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkFile();
  }

  @override
  void didUpdateWidget(covariant SongCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverArtPath != widget.coverArtPath) {
      _checkFile();
    }
  }

  void _checkFile() {
    final path = widget.coverArtPath;
    if (path != null && path.isNotEmpty) {
      _hasFile = true;
      _file = File(path);
    } else {
      _hasFile = false;
      _file = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFile || _file == null) {
      return widget.placeholderBuilder(context, widget.width ?? 44, widget.height ?? 44);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Image.file(
        _file!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            widget.placeholderBuilder(context, widget.width ?? 44, widget.height ?? 44),
      ),
    );
  }
}

Color hashToColor(String id, {Color fallback = const Color(0xFF6B4EE6)}) {
  int hash = 5381;
  for (int i = 0; i < id.length; i++) {
    hash = ((hash << 5) + hash) ^ id.codeUnitAt(i);
  }
  final r = (hash & 0xFF) ~/ 2 + 60;
  final g = ((hash >> 8) & 0xFF) ~/ 2 + 40;
  final b = ((hash >> 16) & 0xFF) ~/ 2 + 80;
  return Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
}
