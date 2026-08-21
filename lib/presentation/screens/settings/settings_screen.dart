import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:celsuis/presentation/providers/settings_provider.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/presentation/themes/now_playing_theme_spec.dart';
import 'package:celsuis/core/utils/color_utils.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSection(
            context,
            'Appearance',
            [
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Theme Preset'),
                trailing: DropdownButton<ThemePreset>(
                  value: settings.themePreset,
                  items: ThemePreset.values.map((preset) => DropdownMenuItem(
                    value: preset,
                    child: Text(_themeLabel(preset)),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      notifier.setThemePreset(value);
                    }
                  },
                ),
              ),
              if (settings.themePreset == ThemePreset.custom) ...[
                ListTile(
                  leading: const Icon(Icons.color_lens),
                  title: const Text('Primary Color'),
                  subtitle: Text(settings.primaryColor ?? '#6750A4'),
                  onTap: () async {
                    final color = await showDialog<Color>(
                      context: context,
                      builder: (ctx) => ColorPickerDialog(initialColor: settings.primaryColor),
                    );
                    if (color != null && context.mounted) {
                      notifier.setPrimaryColor(color);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('Accent Color'),
                  subtitle: Text(settings.accentColor ?? '#03DAC6'),
                  onTap: () async {
                    final color = await showDialog<Color>(
                      context: context,
                      builder: (ctx) => ColorPickerDialog(initialColor: settings.accentColor),
                    );
                    if (color != null && context.mounted) {
                      notifier.setAccentColor(color);
                    }
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.music_note),
                title: const Text('Now Playing Theme'),
                trailing: Text(settings.nowPlayingTheme.name),
                onTap: () async {
                  final selected = await showDialog<NowPlayingTheme>(
                    context: context,
                    builder: (ctx) =>
                        NowPlayingThemePicker(initial: settings.nowPlayingTheme),
                  );
                  if (selected != null && context.mounted) {
                    notifier.setNowPlayingTheme(selected);
                  }
                },
              ),
            ],
          ),
          _buildSection(
            context,
            'Visualization',
            [
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Waveform Style'),
                trailing: Text(settings.waveformStyle.name),
                onTap: () async {
                  final selected = await showDialog<WaveformStyle>(
                    context: context,
                    builder: (ctx) => WaveformStylePicker(initialStyle: settings.waveformStyle),
                  );
                  if (selected != null && context.mounted) {
                    notifier.setWaveformStyle(selected);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.color_lens),
                title: const Text('Waveform Color'),
                subtitle: Text(settings.waveformColor),
                onTap: () async {
                  final color = await showDialog<Color>(
                    context: context,
                    builder: (ctx) => ColorPickerDialog(initialColor: settings.waveformColor),
                  );
                  if (color != null && context.mounted) {
                    notifier.setWaveformColor(color);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('Animation Speed'),
                trailing: Text('${settings.waveformAnimationSpeed}x'),
                onTap: () async {
                  final speed = await showDialog<double>(
                    context: context,
                    builder: (ctx) => SpeedPickerDialog(initialSpeed: settings.waveformAnimationSpeed),
                  );
                  if (speed != null && context.mounted) {
                    notifier.setWaveformAnimationSpeed(speed);
                  }
                },
              ),
            ],
          ),
          _buildSection(
            context,
            'Library',
            [
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Add Folder'),
                subtitle: const Text('Pick a folder to scan for music'),
                onTap: () async {
                  final path = await FilePicker.platform.getDirectoryPath();
                  if (path != null) {
                    ref.read(libraryProvider.notifier).scanFolder(path);
                  }
                },
              ),
              SwitchListTile(
                title: const Text('Auto-scan on Launch'),
                value: settings.autoScanEnabled,
                onChanged: (value) => notifier.toggleAutoScan(value),
              ),
            ],
          ),
          _buildSection(
            context,
            'Playback',
            [
              SwitchListTile(
                title: const Text('Autoplay'),
                subtitle: const Text('Continue playing after the playlist ends'),
                value: settings.autoplayEnabled,
                onChanged: (value) => notifier.toggleAutoplay(value),
              ),
              SwitchListTile(
                title: const Text('Dismiss on Pause'),
                subtitle: const Text('Remove notification when paused'),
                value: settings.stopOnPause,
                onChanged: (value) => notifier.toggleStopOnPause(value),
              ),
            ],
          ),
          _buildSection(
            context,
            'About',
            [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Celsuis'),
                subtitle: const Text('Offline Music Player'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Managed Folders'),
                subtitle: Text('${settings.managedFolders.length} folder(s)'),
                onTap: () => _showManagedFolders(context, ref, settings.managedFolders),
              ),
              const _VersionTile(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  static String _themeLabel(ThemePreset preset) {
    switch (preset) {
      case ThemePreset.system:
        return 'System';
      case ThemePreset.light:
        return 'Light';
      case ThemePreset.dark:
        return 'Dark';
      case ThemePreset.risoZine:
        return 'Riso Zine';
      case ThemePreset.nord:
        return 'Nord';
      case ThemePreset.paperPress:
        return 'Paper Press';
      case ThemePreset.matrix:
        return 'Matrix';
      case ThemePreset.pocketLcd:
        return 'Pocket LCD';
      case ThemePreset.custom:
        return 'Custom';
      case ThemePreset.concrete:
        return 'Concrete';
      case ThemePreset.sumi:
        return 'Sumi Ink';
      case ThemePreset.concreteNoir:
        return 'Concrete Noir';
      case ThemePreset.sumiNight:
        return 'Sumi Night';
    }
  }

  void _showManagedFolders(BuildContext context, WidgetRef ref, List<String> folders) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Managed Folders'),
        content: SizedBox(
          width: double.maxFinite,
          child: folders.isEmpty
              ? const Text('No folders managed yet. Add a folder from the Library tab.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  itemBuilder: (ctx, index) {
                    final folder = folders[index];
                    final name = folder.split('/').last;
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          await ref.read(settingsProvider.notifier).removeManagedFolder(folder);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class ColorPickerDialog extends ConsumerStatefulWidget {
  final String? initialColor;

  const ColorPickerDialog({this.initialColor, super.key});

  @override
  ConsumerState<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends ConsumerState<ColorPickerDialog> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = parseHexColor(widget.initialColor ?? '#6750A4');
  }

  static String _toHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _selectedColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _toHex(_selectedColor),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HsvColorPicker(
            initialColor: _selectedColor,
            onChanged: (color) => setState(() => _selectedColor = color),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              {'color': '#6750A4', 'label': 'Default'},
              {'color': '#D32F2F', 'label': 'Red'},
              {'color': '#1976D2', 'label': 'Blue'},
              {'color': '#388E3C', 'label': 'Green'},
              {'color': '#F57C00', 'label': 'Orange'},
              {'color': '#7B1FA2', 'label': 'Purple'},
              {'color': '#0097A7', 'label': 'Cyan'},
              {'color': '#FF6090', 'label': 'Pink'},
            ]
                .map((map) => ChoiceChip(
                      label: Text(map['label']!),
                      selected: _toHex(_selectedColor).toUpperCase() ==
                          map['color']!.toUpperCase(),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedColor = parseHexColor(map['color']!));
                        }
                      },
                    ))
                .toList(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            Navigator.pop(context, _selectedColor);
          },
          child: const Text('Select'),
        ),
      ],
    );
  }
}

/// Lightweight, dependency-free HSV color picker: a saturation/value box plus a
/// hue bar. Used instead of typing hex codes by hand.
class _HsvColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onChanged;

  const _HsvColorPicker({
    required this.initialColor,
    required this.onChanged,
  });

  @override
  State<_HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<_HsvColorPicker> {
  late HSVColor _color;

  @override
  void initState() {
    super.initState();
    _color = HSVColor.fromColor(widget.initialColor);
  }

  @override
  void didUpdateWidget(covariant _HsvColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync when the dialog seeds a new color (e.g. via a preset chip).
    if (widget.initialColor != oldWidget.initialColor) {
      _color = HSVColor.fromColor(widget.initialColor);
    }
  }

  void _emit(HSVColor updated) {
    setState(() => _color = updated);
    widget.onChanged(updated.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 140,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => _updateSv(d.localPosition, width, height),
                onPanUpdate: (d) => _updateSv(d.localPosition, width, height),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _SvBoxPainter(
                      hue: _color.hue,
                      saturation: _color.saturation,
                      value: _color.value,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 24,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _updateHue(d.localPosition.dx, width),
                onHorizontalDragUpdate: (d) => _updateHue(d.localPosition.dx, width),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    size: Size(width, 24),
                    painter: _HueBarPainter(position: _color.hue / 360),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _updateSv(Offset position, double width, double height) {
    final s = (position.dx / width).clamp(0.0, 1.0);
    final v = (1 - position.dy / height).clamp(0.0, 1.0);
    _emit(_color.withSaturation(s).withValue(v));
  }

  void _updateHue(double dx, double width) {
    final hue = (dx / width * 360).clamp(0.0, 360.0);
    _emit(_color.withHue(hue));
  }
}

class _SvBoxPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  _SvBoxPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    // Solid hue at the top-right, fading to white at the left, then to black
    // at the bottom - a classic saturation/value box.
    final whiteOverlay = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.transparent],
      ).createShader(Offset.zero & size);
    final blackOverlay = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    canvas.drawRect(Offset.zero & size, whiteOverlay);
    canvas.drawRect(Offset.zero & size, blackOverlay);

    // Thumb marker.
    final center = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(center, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SvBoxPainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value;
  }
}

class _HueBarPainter extends CustomPainter {
  final double position;

  _HueBarPainter({required this.position});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(Offset.zero & size),
    );

    final x = position.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(x - 1, 0),
      Offset(x - 1, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HueBarPainter oldDelegate) {
    return oldDelegate.position != position;
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _load(),
      builder: (context, snapshot) {
        return ListTile(
          leading: const Icon(Icons.code),
          title: const Text('Version'),
          subtitle: Text(snapshot.hasData ? snapshot.data! : '…'),
        );
      },
    );
  }

  Future<String> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return 'Unknown';
    }
  }
}

class WaveformStylePicker extends StatelessWidget {
  final WaveformStyle initialStyle;

  const WaveformStylePicker({required this.initialStyle, super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Waveform Style'),
      content: RadioGroup<WaveformStyle>(
        groupValue: initialStyle,
        onChanged: (value) {
          if (value != null) Navigator.pop(context, value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: WaveformStyle.values.map((style) {
            return RadioListTile<WaveformStyle>(
              title: Text(style.name),
              value: style,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class NowPlayingThemePicker extends StatelessWidget {
  final NowPlayingTheme initial;

  const NowPlayingThemePicker({required this.initial, super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Now Playing Theme'),
      content: RadioGroup<NowPlayingTheme>(
        groupValue: initial,
        onChanged: (value) {
          if (value != null) Navigator.pop(context, value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: NowPlayingTheme.values.map((theme) {
            final spec = nowPlayingThemeSpecs[theme]!;
            return RadioListTile<NowPlayingTheme>(
              title: Text(spec.label),
              subtitle: Text(spec.description),
              value: theme,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class SpeedPickerDialog extends StatefulWidget {
  final double initialSpeed;

  const SpeedPickerDialog({required this.initialSpeed, super.key});

  @override
  State<SpeedPickerDialog> createState() => _SpeedPickerDialogState();
}

class _SpeedPickerDialogState extends State<SpeedPickerDialog> {
  late double _currentSpeed;

  @override
  void initState() {
    super.initState();
    _currentSpeed = widget.initialSpeed;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Animation Speed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: _currentSpeed,
            onChanged: (value) => setState(() => _currentSpeed = value),
            min: 0.1,
            max: 3.0,
            divisions: 29,
            label: '${_currentSpeed.toStringAsFixed(1)}x',
          ),
          Text('${_currentSpeed.toStringAsFixed(1)}x'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _currentSpeed),
          child: const Text('Select'),
        ),
      ],
    );
  }
}
