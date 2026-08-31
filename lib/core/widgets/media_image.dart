import 'dart:io';

import 'package:flutter/material.dart';

import '../media/media_service.dart';

/// Displays a media file by its storage `bucket`/`path` pair, resolving
/// through the shared MediaService cache (so offline-queued photos show
/// immediately). Falls back to [placeholder] while loading, if [path] is
/// null, or if the fetch fails.
class MediaImage extends StatefulWidget {
  final String? path;
  final String bucket;
  final Widget placeholder;
  final BoxFit fit;
  final bool public;

  const MediaImage({
    super.key,
    required this.path,
    required this.bucket,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.public = false,
  });

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  File? _file;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      _loadedFor = null;
      _file = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null || path.isEmpty || path == _loadedFor) return;
    _loadedFor = path;

    try {
      final file = await MediaService.instance.getDisplayFile(
        bucket: widget.bucket,
        remotePath: path,
        public: widget.public,
      );
      if (mounted) setState(() => _file = file);
    } catch (_) {
      // Non-fatal — the placeholder stays put.
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.placeholder;
    return Image.file(file, fit: widget.fit);
  }
}
