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

/** Font family for badges */
export const FONT_FAMILY =
  "'Inter', ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";

/** Layout configuration per style */
export const LAYOUT = {
  sm: {
    height: 20,
    iconX: 7,
    iconY: 3.25,
    iconScale: 0.203125,
    fontSize: 11,
    fontWeight: 600,
    dividerWidth: 1,
    textY: 14,
    charWidth: 6,
  },
  md: {
    height: 24,
    iconX: 8,
    iconY: 4,
    iconScale: 0.25,
    fontSize: 13,
    fontWeight: 600,
    dividerWidth: 1,
    textY: 16,
    charWidth: 7,
  },
  lg: {
    height: 32,
    iconX: 11,
    iconY: 5.5,
    iconScale: 0.34,
    fontSize: 16,
    fontWeight: 600,
    dividerWidth: 1,
    textY: 20,
    charWidth: 9,
  },
};
