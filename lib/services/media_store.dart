import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/util/ulid.dart';

/// Keeps picked images inside the app sandbox so notes never depend on the gallery.
abstract interface class MediaStore {
  /// Copies [sourcePath] into app storage and returns the new path.
  Future<String> persistImage(String sourcePath);

  Future<void> delete(String path);
}

class FileMediaStore implements MediaStore {
  Directory? _dir;

  Future<Directory> _mediaDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'media'));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  @override
  Future<String> persistImage(String sourcePath) async {
    // Web has no file system: keep the blob URL for the lifetime of the session.
    if (kIsWeb) return sourcePath;
    final dir = await _mediaDir();
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final target = p.join(dir.path, '${Ulid.next()}$ext');
    await File(sourcePath).copy(target);
    return target;
  }

  @override
  Future<void> delete(String path) async {
    if (kIsWeb) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Best effort: an orphaned file is harmless.
    }
  }
}
