#!/usr/bin/env node
/**
 * Badge generator - creates SVG badges in multiple sizes.
 * @module badges/generate
 */

import { writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { COLORS, SYMBOL_PATH, FONT_FAMILY, LAYOUT } from "./design-tokens.mjs";
import { BADGE_CONFIGS, STYLES } from "./config.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const WEBSITE_ROOT = path.resolve(HERE, "..", "..");
const PUBLIC_DIR = path.join(WEBSITE_ROOT, "public");
const BADGES_DIR = path.join(PUBLIC_DIR, "badges");

/**
 * Escape XML special characters.
 * @param {string} str
 * @returns {string}
 */
function esc(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Generate SVG string for a badge configuration.
 * @param {Object} config
 * @param {string} config.label
 * @param {string} config.message
 * @param {string} config.labelBg
 * @param {string} config.messageBg
 * @param {string} [config.labelColor]
 * @param {string} [config.messageColor]
 * @param {string} style - 'sm', 'md', or 'lg'
 * @returns {string}
 */
function generateSvg(
  { label, message, labelBg, messageBg, labelColor, messageColor },
  style,
) {
  const layout = LAYOUT[style];
  const charWidth = layout.charWidth;

  const labelWidth = label.length * charWidth + 26;
  const messageWidth = message.length * charWidth + 16;
  const svgWidth = labelWidth + messageWidth;
  const height = layout.height;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${svgWidth}" height="${height}" viewBox="0 0 ${svgWidth} ${height}" role="img" aria-label="Glue: ${label} ${message}">
  <title>Glue: ${label} ${message}</title>
  <rect width="${labelWidth}" height="${height}" fill="${labelBg}"/>
  <rect x="${labelWidth}" width="${messageWidth}" height="${height}" fill="${messageBg}"/>
  <rect x="${labelWidth}" width="${layout.dividerWidth}" height="${height}" fill="${COLORS.divider}" opacity="0.65"/>
  <g transform="translate(${layout.iconX} ${layout.iconY}) scale(${layout.iconScale})">
    <path d="${SYMBOL_PATH}" fill="${messageBg}"/>
  </g>
  <text x="26" y="${layout.textY}" fill="${labelColor || COLORS.text}" font-family="${FONT_FAMILY}" font-size="${layout.fontSize}" font-weight="${layout.fontWeight}" text-rendering="geometricPrecision">${esc(label)}</text>
  <text x="${labelWidth + 8}" y="${layout.textY}" fill="${messageColor || COLORS.surface}" font-family="${FONT_FAMILY}" font-size="${layout.fontSize}" font-weight="${layout.fontWeight}" text-rendering="geometricPrecision">${esc(message)}</text>
</svg>`;
}

/**
 * Generate filename for a badge.
 * @param {Object} config
 * @param {string} style
 * @returns {string}
 */
function filenameFor({ label, message, labelBg, messageBg }, style) {
  const labelClean = label.replace(/\s+/g, "-").toLowerCase();
  const labelPrefix =
    labelClean === "glue"
      ? ""
      : labelClean.startsWith("glue-")
        ? labelClean.slice(5) + "-"
        : labelClean + "-";

  const msgClean = message.replace(/\s+/g, "-").toLowerCase();
  const labelBgSafe = labelBg.replace("#", "").toLowerCase();
  const msgBgSafe = messageBg.replace("#", "").toLowerCase();

  return `glue-${labelPrefix}${msgClean}-${style}-${labelBgSafe}-${msgBgSafe}`;
}

/**
 * Main entry point.
 */
async function main() {
  await mkdir(BADGES_DIR, { recursive: true });

  console.log("Generating badges...");

  /** @type {Object[]} */
  const jsonBadges = [];

  for (const config of BADGE_CONFIGS) {
    for (const style of STYLES) {
      const fileBase = filenameFor(config, style);
      const svg = generateSvg(config, style);

      const svgPath = path.join(BADGES_DIR, `${fileBase}.svg`);
      await writeFile(svgPath, svg, "utf-8");

      jsonBadges.push({
        id: fileBase,
        file: `${fileBase}.svg`,
        label: config.label,
        message: config.message,
        labelBg: config.labelBg,
        messageBg: config.messageBg,
        labelColor: config.labelColor || COLORS.text,
        messageColor: config.messageColor || COLORS.surface,
        category: config.category,
        style,
      });

      console.log(`  → ${fileBase}.svg`);
    }
  }

  const jsonOutput = JSON.stringify(jsonBadges, null, 2);
  await writeFile(path.join(BADGES_DIR, "badges.json"), jsonOutput, "utf-8");
  console.log("  → badges.json");

  const total = BADGE_CONFIGS.length * STYLES.length;
  console.log(`✓ generated ${total} badges in public/badges/`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
