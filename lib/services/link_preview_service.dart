import 'dart:async';

import 'package:http/http.dart' as http;

/// Title / description / image of a web page (Open Graph aware).
class LinkPreview {
  const LinkPreview({this.title, this.description, this.imageUrl});

  final String? title;
  final String? description;
  final String? imageUrl;

  bool get isEmpty => title == null && description == null && imageUrl == null;
}

/// Fetches page metadata with a short timeout and a size cap. Failures are silent: a link note
/// simply keeps showing its host name when offline or blocked (e.g. by CORS on web).
class LinkPreviewService {
  LinkPreviewService(this._client);

  final http.Client _client;

  Future<LinkPreview?> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return null;
    try {
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (compatible; PersonalStorage/1.0; +link-preview)',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) return null;
      final type = response.headers['content-type'] ?? '';
      if (type.isNotEmpty && !type.contains('html')) return null;
      final bytes = response.bodyBytes;
      final head = String.fromCharCodes(bytes.length > 400 * 1024 ? bytes.sublist(0, 400 * 1024) : bytes);
      return parse(head, baseUri: uri);
    } on Object {
      return null;
    }
  }

  /// Pure parsing step (unit-tested).
  static LinkPreview parse(String html, {Uri? baseUri}) {
    String? meta(String key) {
      final patterns = [
        RegExp('<meta[^>]+(?:property|name)=["\']$key["\'][^>]*content=["\']([^"\']*)["\']', caseSensitive: false),
        RegExp('<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$key["\']', caseSensitive: false),
      ];
      for (final p in patterns) {
        final m = p.firstMatch(html);
        if (m != null && m.group(1)!.trim().isNotEmpty) return _decode(m.group(1)!);
      }
      return null;
    }

    final titleTag = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1);
    final title = meta('og:title') ?? meta('twitter:title') ?? (titleTag == null ? null : _decode(titleTag));
    var image = meta('og:image') ?? meta('twitter:image');
    if (image != null && baseUri != null) image = baseUri.resolve(image).toString();
    String? clean(String? s) {
      final t = s?.replaceAll(RegExp(r'\s+'), ' ').trim();
      return t == null || t.isEmpty ? null : (t.length > 300 ? '${t.substring(0, 300)}…' : t);
    }

    return LinkPreview(
      title: clean(title),
      description: clean(meta('og:description') ?? meta('description') ?? meta('twitter:description')),
      imageUrl: image,
    );
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
}
