/**
 * Badge configuration - definitions for all badge variants.
 * @module badges/config
 */

import { COLORS } from "./design-tokens.mjs";

/**
 * @typedef {Object} BadgeConfig
 * @property {string} label - Left side text
 * @property {string} message - Right side text
 * @property {string} labelBg - Background color for label
 * @property {string} messageBg - Background color for message
 * @property {string} [labelColor] - Text color for label
 * @property {string} [messageColor] - Text color for message
 * @property {string} category - Badge category
 */

/** @type {BadgeConfig[]} */
export const BADGE_CONFIGS = [
  // Status badges
  {
    label: "Glue",
    message: "agent-ready",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "status",
  },
  {
    label: "Glue",
    message: "terminal-agent",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "status",
  },
  {
    label: "Glue",
    message: "repo-aware",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "status",
  },
  {
    label: "Glue",
    message: "tool-ready",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "status",
  },
  {
    label: "Glue",
    message: "local-first",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "status",
  },
  {
    label: "Glue",
    message: "passing",
    labelBg: COLORS.surface,
    messageBg: COLORS.success,
    category: "status",
  },
  {
    label: "Glue",
    message: "active",
    labelBg: COLORS.surface,
    messageBg: COLORS.success,
    category: "status",
  },
  {
    label: "Glue",
    message: "warning",
    labelBg: COLORS.surface,
    messageBg: COLORS.warning,
    category: "status",
  },
  {
    label: "Glue",
    message: "failed",
    labelBg: COLORS.surface,
    messageBg: COLORS.error,
    category: "status",
  },
  {
    label: "Glue",
    message: "paused",
    labelBg: COLORS.surface,
    messageBg: COLORS.muted,
    category: "status",
  },
  {
    label: "Glue",
    message: "experimental",
    labelBg: COLORS.surface,
    messageBg: COLORS.purple,
    category: "status",
  },
  {
    label: "Glue",
    message: "info",
    labelBg: COLORS.surface,
    messageBg: COLORS.info,
    category: "status",
  },

  // Brand badges
  {
    label: "built with",
    message: "Glue",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "brand",
  },
  {
    label: "powered by",
    message: "Glue",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "brand",
  },
  {
    label: "agent",
    message: "Glue",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "brand",
  },
  {
    label: "uses",
    message: "Glue",
    labelBg: COLORS.divider,
    messageBg: COLORS.accent,
    category: "brand",
  },
  {
    label: "Glue",
    message: "quiet-agent",
    labelBg: COLORS.surface,
    messageBg: COLORS.divider,
    messageColor: COLORS.text,
    category: "brand",
  },
  {
    label: "Glue",
    message: "no-hype",
    labelBg: COLORS.surface,
    messageBg: COLORS.divider,
    messageColor: COLORS.text,
    category: "brand",
  },
  {
    label: "Glue",
    message: "not-magic",
    labelBg: COLORS.surface,
    messageBg: COLORS.divider,
    messageColor: COLORS.text,
    category: "brand",
  },
  {
    label: "Glue",
    message: "terminal-native",
    labelBg: COLORS.surface,
    messageBg: COLORS.divider,
    messageColor: COLORS.text,
    category: "brand",
  },

  // Reverse badges
  {
    label: "Glue",
    message: "agent-ready",
    labelBg: COLORS.accent,
    messageBg: COLORS.surface,
    labelColor: COLORS.surface,
    messageColor: COLORS.text,
    category: "reverse",
  },
  {
    label: "built with",
    message: "Glue",
    labelBg: COLORS.accent,
    messageBg: COLORS.surface,
    labelColor: COLORS.surface,
    messageColor: COLORS.text,
    category: "reverse",
  },

  // Meme / quirky badges
  {
    label: "Glue",
    message: "its-giving",
    labelBg: COLORS.surface,
    messageBg: COLORS.purple,
    category: "meme",
  },
  {
    label: "Glue",
    message: "no-cap",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    messageColor: COLORS.text,
    category: "meme",
  },
  {
    label: "Glue",
    message: "fr-fr",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "meme",
  },
  {
    label: "Glue",
    message: "beta-but",
    labelBg: COLORS.surface,
    messageBg: COLORS.purple,
    category: "meme",
  },
  {
    label: "Glue",
    message: "works-on-my",
    labelBg: COLORS.surface,
    messageBg: COLORS.error,
    category: "meme",
  },
  {
    label: "Glue",
    message: "tm-technically",
    labelBg: COLORS.surface,
    messageBg: COLORS.muted,
    category: "meme",
  },
  {
    label: "Glue",
    message: "glue-goo",
    labelBg: COLORS.accent,
    messageBg: COLORS.surface,
    labelColor: COLORS.surface,
    messageColor: COLORS.text,
    category: "meme",
  },
  {
    label: "Glue",
    message: "粘性但",
    labelBg: COLORS.surface,
    messageBg: COLORS.accent,
    category: "meme",
  },
  {
    label: "Glue",
    message: "basically-magic",
    labelBg: COLORS.surface,
    messageBg: COLORS.purple,
    category: "meme",
  },
];

/**
 * Styles to generate for each badge.
 */
export const STYLES = ["sm", "md", "lg"];
