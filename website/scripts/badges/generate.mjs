#!/usr/bin/env node
/**
 * Badge generator - creates SVG and PNG badges in multiple sizes.
 * @module badges/generate
 */

import { writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

import {
  COLORS,
  SYMBOL_PATH,
  SYMBOL_VIEWBOX,
  FONT_FAMILY,
  LAYOUT,
} from "./design-tokens.mjs";
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
 * @param {boolean} [config.showIcon]
 * @param {string} style - 'sm', 'md', or 'lg'
 * @returns {string}
 */
/**
 * Derives badge geometry from the per-style [LAYOUT] constants.
 *
 *   labelTextX   = showIcon ? iconVisualRight + iconTextGap : textPadX
 *   labelWidth   = ceil(labelTextX + labelTextWidth + textPadX)
 *   messageTextX = labelWidth + textPadX
 *   messageWidth = ceil(textPadX + messageTextWidth + textPadX)
 *
 * Replaces the previous hard-coded `+ 26` / `text x="26"` formulas
 * which sized everything to the sm icon and broke as the icon
 * scaled up — md squeezed the icon-text gap to 5px, lg overlapped
 * text into the icon by 2.7px, every size had zero right padding on
 * the label.
 */
function deriveGeometry(layout, label, message, showIcon) {
  const iconVisualRight =
    layout.iconX +
    (SYMBOL_VIEWBOX.xMin + SYMBOL_VIEWBOX.width) * layout.iconScale;
  const labelTextX = showIcon
    ? iconVisualRight + layout.iconTextGap
    : layout.textPadX;

  const labelTextWidth = label.length * layout.charWidth;
  // Ceil so a wide-glyph string never clips by a sub-pixel.
  const labelWidth = Math.ceil(labelTextX + labelTextWidth + layout.textPadX);

  const messageTextX = labelWidth + layout.textPadX;
  const messageTextWidth = message.length * layout.charWidth;
  const messageWidth = Math.ceil(
    layout.textPadX + messageTextWidth + layout.textPadX,
  );

  return { labelTextX, labelWidth, messageTextX, messageWidth };
}

function generateSvg(
  {
    label,
    message,
    labelBg,
    messageBg,
    labelColor,
    messageColor,
    showIcon = true,
  },
  style,
) {
  const layout = LAYOUT[style];
  const { labelTextX, labelWidth, messageTextX, messageWidth } =
    deriveGeometry(layout, label, message, showIcon);
  const svgWidth = labelWidth + messageWidth;
  const height = layout.height;

  const iconGroup = showIcon
    ? `<g transform="translate(${layout.iconX} ${layout.iconY}) scale(${layout.iconScale})">
      <path d="${SYMBOL_PATH}" fill="${messageBg}"/>
    </g>`
    : "";

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${svgWidth}" height="${height}" viewBox="0 0 ${svgWidth} ${height}" role="img" aria-label="Glue: ${label} ${message}">
  <title>Glue: ${label} ${message}</title>
  <defs>
    <clipPath id="r">
      <rect width="${svgWidth}" height="${height}" rx="0" fill="#fff"/>
    </clipPath>
  </defs>
  <g clip-path="url(#r)">
    <rect width="${labelWidth}" height="${height}" fill="${labelBg}"/>
    <rect x="${labelWidth}" width="${messageWidth}" height="${height}" fill="${messageBg}"/>
    <rect x="${labelWidth}" width="${layout.dividerWidth}" height="${height}" fill="${COLORS.divider}" opacity="0.65"/>
    ${iconGroup}
    <text x="${labelTextX}" y="${layout.textY}" fill="${labelColor || COLORS.text}" font-family="${FONT_FAMILY}" font-size="${layout.fontSize}" font-weight="${layout.fontWeight}" text-rendering="geometricPrecision">${esc(label)}</text>
    <text x="${messageTextX}" y="${layout.textY}" fill="${messageColor || COLORS.surface}" font-family="${FONT_FAMILY}" font-size="${layout.fontSize}" font-weight="${layout.fontWeight}" text-rendering="geometricPrecision">${esc(message)}</text>
  </g>
</svg>`;
}

/**
 * Generate PNG buffer from SVG string.
 * @param {string} svg
 * @returns {Promise<Buffer>}
 */
async function renderPng(svg) {
  const resvg = new Resvg(svg);
  return resvg.render().asPng();
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

      // Write SVG
      const svgPath = path.join(BADGES_DIR, `${fileBase}.svg`);
      await writeFile(svgPath, svg, "utf-8");

      // Write PNG
      const pngBuffer = await renderPng(svg);
      const pngPath = path.join(BADGES_DIR, `${fileBase}.png`);
      await writeFile(pngPath, pngBuffer);

      jsonBadges.push({
        id: fileBase,
        file: `${fileBase}.svg`,
        pngFile: `${fileBase}.png`,
        label: config.label,
        message: config.message,
        labelBg: config.labelBg,
        messageBg: config.messageBg,
        labelColor: config.labelColor || COLORS.text,
        messageColor: config.messageColor || COLORS.surface,
        category: config.category,
        style,
      });

      console.log(`  → ${fileBase}.svg + .png`);
    }
  }

  // Write JSON manifest
  const jsonOutput = JSON.stringify(jsonBadges, null, 2);
  await writeFile(path.join(BADGES_DIR, "badges.json"), jsonOutput, "utf-8");
  console.log("  → badges.json");

  const total = BADGE_CONFIGS.length * STYLES.length;
  console.log(
    `✓ generated ${total} badges (${total * 2} files) in public/badges/`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
