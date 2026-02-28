import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

class HtmlToMarkdown {
  static String convert(String html) {
    if (html.trim().isEmpty) return '';

    final doc = html_parser.parseFragment(html);
    final buf = StringBuffer();
    _convertNodes(doc.nodes, buf);
    return _cleanup(buf.toString());
  }

  static void _convertNodes(List<Node> nodes, StringBuffer buf) {
    for (final node in nodes) {
      if (node is Text) {
        buf.write(_collapseWhitespace(node.text));
      } else if (node is Element) {
        _convertElement(node, buf);
      }
    }
  }

  static void _convertElement(Element el, StringBuffer buf) {
    final tag = el.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(tag.substring(1));
        final prefix = '#' * level;
        buf.write('$prefix ');
        _convertNodes(el.nodes, buf);
        buf.write('\n\n');

      case 'p':
        _convertNodes(el.nodes, buf);
        buf.write('\n\n');

      case 'br':
        buf.write('\n');

      case 'hr':
        buf.write('\n---\n\n');

      case 'strong' || 'b':
        buf.write('**');
        _convertNodes(el.nodes, buf);
        buf.write('**');

      case 'em' || 'i':
        buf.write('*');
        _convertNodes(el.nodes, buf);
        buf.write('*');

      case 'code':
        if (_isInsidePre(el)) {
          _convertNodes(el.nodes, buf);
        } else {
          buf.write('`');
          buf.write(el.text);
          buf.write('`');
        }

      case 'pre':
        final codeEl = el.querySelector('code');
        final lang = _detectLang(codeEl);
        buf.write('\n```$lang\n');
        buf.write((codeEl ?? el).text.trim());
        buf.write('\n```\n\n');

      case 'a':
        final href = el.attributes['href'] ?? '';
        buf.write('[');
        _convertNodes(el.nodes, buf);
        buf.write(']($href)');

      case 'img':
        final src = el.attributes['src'] ?? '';
        final alt = el.attributes['alt'] ?? '';
        buf.write('![$alt]($src)');

      case 'ul':
        buf.write('\n');
        for (final li in el.children.where((c) => c.localName == 'li')) {
          buf.write('- ');
          _convertNodes(li.nodes, buf);
          buf.write('\n');
        }
        buf.write('\n');

      case 'ol':
        buf.write('\n');
        var i = 1;
        for (final li in el.children.where((c) => c.localName == 'li')) {
          buf.write('$i. ');
          _convertNodes(li.nodes, buf);
          buf.write('\n');
          i++;
        }
        buf.write('\n');

      case 'blockquote':
        final inner = StringBuffer();
        _convertNodes(el.nodes, inner);
        for (final line in inner.toString().trim().split('\n')) {
          buf.write('> $line\n');
        }
        buf.write('\n');

      case 'table':
        _convertTable(el, buf);

      default:
        _convertNodes(el.nodes, buf);
    }
  }

  static bool _isInsidePre(Element el) {
    Element? current = el.parent;
    while (current != null) {
      if (current.localName == 'pre') return true;
      current = current.parent;
    }
    return false;
  }

  static String _detectLang(Element? codeEl) {
    if (codeEl == null) return '';
    final cls = codeEl.className;
    final match = RegExp(r'language-(\w+)').firstMatch(cls);
    return match?.group(1) ?? '';
  }

  static void _convertTable(Element table, StringBuffer buf) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return;

    buf.write('\n');
    for (var r = 0; r < rows.length; r++) {
      final cells = rows[r].querySelectorAll('th, td');
      final line = cells.map((c) => c.text.trim()).join(' | ');
      buf.write('| $line |\n');
      if (r == 0) {
        buf.write('| ${cells.map((_) => '---').join(' | ')} |\n');
      }
    }
    buf.write('\n');
  }

  static String _collapseWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ');

  static String _cleanup(String s) =>
      s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim() +
      (s.trim().isNotEmpty ? '\n' : '');
}
