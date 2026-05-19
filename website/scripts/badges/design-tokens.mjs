/**
 * Badge design tokens - colors, dimensions, and icon paths.
 * @module badges/design-tokens
 */

/** Brand colors */
export const COLORS = {
  accent: "#FACC15",
  surface: "#0A0A0B",
  surfaceLight: "#FFFFFF",
  divider: "#222326",
  text: "#E6E6E6",
  textLight: "#111111",
  success: "#22C55E",
  warning: "#EAB308",
  error: "#EF4444",
  info: "#3B82F6",
  muted: "#64748B",
  purple: "#A855F7",
};

/** Glue drop symbol path */
export const SYMBOL_PATH =
  "M32 4 C32 4, 52 24, 52 36 C52 48, 43.3 58, 32 58 C20.7 58, 12 48, 12 36 C12 24, 32 4, 32 4Z";

/**
 * Source-space bounding box of [SYMBOL_PATH]. Used by the badge
 * generator to derive the icon's visual right edge so text doesn't
 * overlap the icon at large sizes — previously the text x was
 * hard-coded to 26 regardless of icon scale, which made the "G" of
 * "Glue" overlap the icon at lg (overlap measured at 2.7px).
 */
export const SYMBOL_VIEWBOX = { xMin: 12, yMin: 4, width: 40, height: 54 };

/** Font family for badges */
export const FONT_FAMILY =
  "'Inter', ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";

/**
 * Per-style layout constants.
 *
 * Geometry rule (mirrors shields.io's `lib/badge-renderers.js`):
 *
 *   [iconX][icon][iconTextGap][label-text][textPadX][divider]
 *   [textPadX][message-text][textPadX]
 *
 * The generator derives both rect widths and text x positions from
 * these named constants — no hardcoded magic numbers like the
 * previous `+ 26` / `text x="26"` which broke as icons scaled up.
 *
 * - `iconX` / `iconY` / `iconScale` are the SVG `<g transform>` values
 *   for the symbol path. Combined with [SYMBOL_VIEWBOX] they yield
 *   the icon's visible right edge inside the label rect.
 * - `iconTextGap` is the horizontal space between the icon's visible
 *   right edge and the start of the label text.
 * - `textPadX` is the horizontal padding around text on *both* sides
 *   (label-right, message-left, message-right). Without it, the label
 *   text sat flush against the rect/divider edge.
 * - `charWidth` is an empirical average glyph width for Inter
 *   SemiBold at `fontSize` — slightly over-allocated so a real
 *   wide-glyph string never clips.
 */
export const LAYOUT = {
  sm: {
    height: 20,
    fontSize: 11,
    fontWeight: 600,
    charWidth: 6.2,
    iconX: 7,
    iconY: 3.25,
    iconScale: 0.203125,
    iconTextGap: 8,
    textPadX: 8,
    dividerWidth: 1,
    textY: 14,
  },
  md: {
    height: 24,
    fontSize: 13,
    fontWeight: 600,
    charWidth: 7.3,
    iconX: 8,
    iconY: 4,
    iconScale: 0.25,
    iconTextGap: 9,
    textPadX: 9,
    dividerWidth: 1,
    textY: 16,
  },
  lg: {
    height: 32,
    fontSize: 16,
    fontWeight: 600,
    charWidth: 9.0,
    iconX: 11,
    iconY: 5.5,
    iconScale: 0.34,
    iconTextGap: 12,
    textPadX: 11,
    dividerWidth: 1,
    textY: 20,
  },
};
