/// Shared brand and severity-marker glyphs used across the Glue CLI surface
/// (`catalog`, `doctor`, `serve`, …). Centralized so every command renders a
/// consistent header style.
library;

import 'package:glue/src/terminal/styled.dart';

/// Brand dot used as a leading glyph in section headers (e.g.
/// `● Glue Catalog`). The RGB matches the brand yellow elsewhere in the
/// product (favicon, OG images).
String get brandDot => '●'.styled.rgb(250, 204, 21).toString();

/// Severity markers used by status-line output. Shape and color match
/// `doctor` so every command reads as a sibling surface.
String get markerOk => '✓'.styled.green.toString();
String get markerInfo => '·'.styled.gray.toString();
String get markerWarn => '!'.styled.yellow.toString();
String get markerError => '✗'.styled.red.toString();
