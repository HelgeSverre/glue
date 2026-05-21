/// Shared brand and severity-marker glyphs used across the Glue CLI surface
/// (`catalog`, `doctor`, `acp`, …). Centralized so every command renders a
/// consistent header style.
///
/// All markers go through `styledOrPlain` so they collapse to a plain glyph
/// when stdout is not a TTY or `NO_COLOR` is set — `glue … | grep` stays
/// readable.
library;

import 'package:glue/src/terminal/tty_style.dart';

/// Brand dot used as a leading glyph in section headers (e.g.
/// `● Glue Catalog`). The RGB matches the brand yellow elsewhere in the
/// product (favicon, OG images).
String get brandDot => styledOrPlain('●', (s) => s.rgb(250, 204, 21));

/// Severity markers used by status-line output. Shape and color match
/// `doctor` so every command reads as a sibling surface.
String get markerOk => styledOrPlain('✓', (s) => s.green);
String get markerInfo => styledOrPlain('·', (s) => s.gray);
String get markerWarn => styledOrPlain('!', (s) => s.yellow);
String get markerError => styledOrPlain('✗', (s) => s.red);
