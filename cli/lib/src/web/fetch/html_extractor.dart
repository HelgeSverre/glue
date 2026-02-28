import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

class HtmlExtractor {
  static const _noiseTagNames = {
    'script',
    'style',
    'noscript',
    'svg',
    'canvas',
    'iframe',
    'nav',
    'footer',
    'header',
    'aside',
    'form',
    'button',
    'input',
    'select',
    'textarea',
    'dialog',
  };

  static String extract(String html) {
    if (html.trim().isEmpty) return '';

    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return _collapseWhitespace(doc.outerHtml);

    _stripNoiseTags(body);

    final candidate = _findBestCandidate(body);
    return candidate.innerHtml.trim();
  }

  static void _stripNoiseTags(Element root) {
    final toRemove = <Element>[];
    for (final element in root.querySelectorAll('*')) {
      if (_noiseTagNames.contains(element.localName?.toLowerCase())) {
        toRemove.add(element);
      }
    }
    for (final el in toRemove) {
      el.remove();
    }
  }

  static Element _findBestCandidate(Element body) {
    for (final selector in ['article', 'main', '[role="main"]']) {
      final el = body.querySelector(selector);
      if (el != null && _textLength(el) > 100) return el;
    }

    Element best = body;
    int bestScore = 0;

    for (final el in body.querySelectorAll('div, section')) {
      final score = _scoreCandidate(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    return best;
  }

  static int _scoreCandidate(Element el) {
    final text = _textLength(el);
    if (text < 100) return 0;

    final paragraphs = el.querySelectorAll('p').length;
    final links = el.querySelectorAll('a').length;
    final linkDensity = text > 0 ? (links * 30) / text : 1.0;

    if (linkDensity > 0.5) return 0;

    return text + (paragraphs * 50);
  }

  static int _textLength(Element el) => _collapseWhitespace(el.text).length;

  static String _collapseWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
