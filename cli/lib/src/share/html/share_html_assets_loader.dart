import 'dart:io';

import 'package:path/path.dart' as p;

class ShareHtmlAssetsLoader {
  const ShareHtmlAssetsLoader();

  String loadTemplate() => _loadAsset('share_page_template.html');

  String loadStylesheet() => _loadAsset('share_page.css');

  String _loadAsset(String fileName) {
    final candidates = [
      p.join('lib', 'src', 'share', 'html', fileName),
      p.join('cli', 'lib', 'src', 'share', 'html', fileName),
    ];

    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) return file.readAsStringSync();
    }

    throw StateError('Share HTML asset not found: $fileName');
  }
}
