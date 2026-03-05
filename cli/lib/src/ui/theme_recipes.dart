import 'package:glue/src/ui/theme_tokens.dart';

class GlueRecipes {
  final GlueThemeTokens t;

  const GlueRecipes(this.t);

  String brandHeading(String title, {String? subtitle}) {
    final left = t.accent('${t.brandDot} $title');
    if (subtitle == null || subtitle.isEmpty) return left;
    return '$left  ${t.textMuted(subtitle)}';
  }

  String sectionHeading(String title) => t.accent('${t.brandDot} $title');

  String keyHint(String key, String description) {
    return '${t.accent('[${key.toUpperCase()}]')} ${t.textSecondary(description)}';
  }

  String badge(String label, {GlueTone tone = GlueTone.accent}) {
    final paint = t.tone(tone);
    return paint(' $label ');
  }

  String listItem(
    String label, {
    required bool selected,
    String? description,
  }) {
    final marker = selected ? t.accent('${t.brandDot} ') : '  ';
    final body = selected ? t.selection(label) : t.textPrimary(label);
    if (description == null || description.isEmpty) {
      return '$marker$body';
    }
    return '$marker$body  ${t.textMuted(description)}';
  }

  String borderLine(int width, {String? title}) {
    if (width < 4) return '';
    if (title == null || title.isEmpty) {
      return t.surfaceBorder('┌${'─' * (width - 2)}┐');
    }
    final tag = ' $title ';
    final innerWidth = width - 2;
    final left = '─' * 1;
    final rightCount = innerWidth - left.length - tag.length;
    final right = '─' * (rightCount > 0 ? rightCount : 0);
    return t.surfaceBorder('┌$left') +
        t.accentSubtle(tag) +
        t.surfaceBorder('$right┐');
  }

  String panelRow(int width, String content) {
    final visible = content.length > width - 4
        ? '${content.substring(0, width - 5)}…'
        : content;
    final pad = ' ' * ((width - 4) - visible.length).clamp(0, width);
    return '${t.surfaceBorder('│ ')}$visible$pad${t.surfaceBorder(' │')}';
  }
}
