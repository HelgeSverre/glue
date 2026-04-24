import 'package:glue/src/terminal/styled.dart';

// TODO: only used in the demo app.

enum GlueThemeMode { minimal, highContrast }

enum GlueTone { accent, info, success, warning, danger, muted }

typedef GlueStyleFn = String Function(String text);

class GlueThemeTokens {
  final GlueThemeMode mode;
  final String brandDot;

  final GlueStyleFn textPrimary;
  final GlueStyleFn textSecondary;
  final GlueStyleFn textMuted;
  final GlueStyleFn accent;
  final GlueStyleFn accentSubtle;

  final GlueStyleFn surfaceBorder;
  final GlueStyleFn surfaceMuted;
  final GlueStyleFn focus;
  final GlueStyleFn selection;

  final GlueStyleFn info;
  final GlueStyleFn success;
  final GlueStyleFn warning;
  final GlueStyleFn danger;

  const GlueThemeTokens({
    required this.mode,
    this.brandDot = '●',
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSubtle,
    required this.surfaceBorder,
    required this.surfaceMuted,
    required this.focus,
    required this.selection,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
  });

  GlueStyleFn tone(GlueTone tone) {
    return switch (tone) {
      GlueTone.accent => accent,
      GlueTone.info => info,
      GlueTone.success => success,
      GlueTone.warning => warning,
      GlueTone.danger => danger,
      GlueTone.muted => textMuted,
    };
  }
}

GlueThemeTokens glueThemeTokens(GlueThemeMode mode) {
  switch (mode) {
    case GlueThemeMode.minimal:
      return GlueThemeTokens(
        mode: mode,
        textPrimary: (text) => text,
        textSecondary: (text) => text.styled.gray.toString(),
        textMuted: (text) => text.styled.dim.toString(),
        accent: (text) => text.styled.bold.yellow.toString(),
        accentSubtle: (text) => text.styled.fg256(229).toString(),
        surfaceBorder: (text) => text.styled.gray.toString(),
        surfaceMuted: (text) => text.styled.bg256(236).white.toString(),
        focus: (text) => text.styled.underline.toString(),
        selection: (text) => text.styled.bg256(236).yellow.toString(),
        info: (text) => text.styled.cyan.toString(),
        success: (text) => text.styled.green.toString(),
        warning: (text) => text.styled.yellow.toString(),
        danger: (text) => text.styled.red.toString(),
      );
    case GlueThemeMode.highContrast:
      return GlueThemeTokens(
        mode: mode,
        textPrimary: (text) => text.styled.brightWhite.toString(),
        textSecondary: (text) => text.styled.white.toString(),
        textMuted: (text) => text.styled.gray.toString(),
        accent: (text) => text.styled.bold.yellow.toString(),
        accentSubtle: (text) => text.styled.brightYellow.toString(),
        surfaceBorder: (text) => text.styled.brightWhite.toString(),
        surfaceMuted: (text) => text.styled.bg256(236).white.toString(),
        focus: (text) => text.styled.inverse.toString(),
        selection: (text) => text.styled.bgYellow.black.toString(),
        info: (text) => text.styled.brightCyan.toString(),
        success: (text) => text.styled.brightGreen.toString(),
        warning: (text) => text.styled.brightYellow.toString(),
        danger: (text) => text.styled.brightRed.toString(),
      );
  }
}

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
