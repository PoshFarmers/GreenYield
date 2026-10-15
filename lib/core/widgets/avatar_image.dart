import 'package:flutter/material.dart';

import '../storage/avatar_cache_service.dart';

class AvatarImage extends StatefulWidget {
  final String? path;
  final double radius;

  const AvatarImage({super.key, required this.path, this.radius = 48});

  @override
  State<AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends State<AvatarImage> {
  final _cacheService = AvatarCacheService();
  ImageProvider? _image;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      _loadedFor = null;
      final path = widget.path;
      if (path == null || path.isEmpty) {
        _image = null;
      } else {
        // Keep showing the current image until the new one is ready, instead
        // of flashing the placeholder icon.
        _load();
      }
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null || path.isEmpty || path == _loadedFor) return;
    _loadedFor = path;

    try {
      final file = await _cacheService.getAvatarFile(path);
      // Ignore results for a path that's no longer current.
      if (mounted && widget.path == path) {
        setState(() => _image = FileImage(file));
      }
    } catch (_) {
      // Non-fatal: fall back to the placeholder icon (never keep a previous
      // person's avatar for a path that failed to load).
      if (mounted && widget.path == path) setState(() => _image = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundImage: _image,
      child: _image == null ? Icon(Icons.person, size: widget.radius) : null,
    );
  }
}
