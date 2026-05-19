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
 * Source-space bounding box of [SYMBOL_PATH]. The generator multiplies
 * `iconX + (xMin + width) * iconScale` to find the icon's visible
 * right edge, which becomes the anchor for the label text's left
 * position. Without this, text x would have to be hardcoded per
 * size and would overlap the icon as it scales up.
 */
export const SYMBOL_VIEWBOX = { xMin: 12, yMin: 4, width: 40, height: 54 };

/** Font family for badges */
export const FONT_FAMILY =
  "'Inter', ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";

/**
 * Per-style layout constants. The generator (`generate.mjs`) derives
 * every rect width and text x from these — no magic numbers in the
 * generator.
 *
 *   [iconX][icon][iconTextGap][label-text][textPadX] | [textPadX][message-text][textPadX]
 *
 * - `iconX` / `iconY` / `iconScale` — SVG `<g transform>` values for
 *   the symbol path. With [SYMBOL_VIEWBOX] they yield the icon's
 *   visible right edge.
 * - `iconTextGap` — horizontal space between the icon's visible
 *   right edge and the label text.
 * - `textPadX` — horizontal padding around text on both sides
 *   (label-right, message-left, message-right). Symmetric.
 * - `charWidth` — empirical average glyph width for Inter SemiBold
 *   at `fontSize`. Slightly over-allocated so wide-glyph strings
 *   never clip. `Math.ceil` rounding on the final width adds a
 *   sub-pixel safety margin.
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
