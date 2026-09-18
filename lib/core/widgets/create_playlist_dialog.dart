import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsius/presentation/providers/playlist_provider.dart';

class CreatePlaylistDialog extends StatelessWidget {
  const CreatePlaylistDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return AlertDialog(
      title: const Text('New Playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            Navigator.pop(context, value.trim());
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

Future<String?> showCreatePlaylistDialog(BuildContext context, WidgetRef ref) async {
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => const CreatePlaylistDialog(),
  );
  if (name != null && name.trim().isNotEmpty) {
    ref.read(playlistProvider.notifier).createPlaylist(name.trim());
    return name;
  }
  return null;
}
