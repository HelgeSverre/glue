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
 * Derives badge geometry from the per-style [LAYOUT] constants.
 *
 *   labelTextX   = showIcon ? iconVisualRight + iconTextGap : textPadX
 *   labelWidth   = ceil(labelTextX + labelTextWidth + textPadX)
 *   messageTextX = labelWidth + textPadX
 *   messageWidth = ceil(textPadX + messageTextWidth + textPadX)
 *
 * Widths use `Math.ceil` so wide-glyph strings never clip sub-pixel.
 *
 * @param {object} layout       Per-style entry from [LAYOUT].
 * @param {string} label        Left text.
 * @param {string} message      Right text.
 * @param {boolean} showIcon    Whether the badge has an icon.
 * @returns {{labelTextX:number,labelWidth:number,messageTextX:number,messageWidth:number}}
 */
function deriveGeometry(layout, label, message, showIcon) {
  const iconVisualRight =
    layout.iconX +
    (SYMBOL_VIEWBOX.xMin + SYMBOL_VIEWBOX.width) * layout.iconScale;
  const labelTextX = showIcon
    ? iconVisualRight + layout.iconTextGap
    : layout.textPadX;

  const labelTextWidth = label.length * layout.charWidth;
  const labelWidth = Math.ceil(labelTextX + labelTextWidth + layout.textPadX);

  const messageTextX = labelWidth + layout.textPadX;
  const messageTextWidth = message.length * layout.charWidth;
  const messageWidth = Math.ceil(
    layout.textPadX + messageTextWidth + layout.textPadX,
  );

  return { labelTextX, labelWidth, messageTextX, messageWidth };
}

/**
 * Generate a badge SVG plus the dimensions it was sized at — returning
 * both lets the manifest record real `width`/`height` without
 * re-parsing the SVG string we just produced.
 *
 * @param {object} config           Badge config from `./config.mjs`.
 * @param {string} config.label
 * @param {string} config.message
 * @param {string} config.labelBg
 * @param {string} config.messageBg
 * @param {string} [config.labelColor]
 * @param {string} [config.messageColor]
 * @param {boolean} [config.showIcon=true]
 * @param {'sm'|'md'|'lg'} style
 * @param {number} [cornerRadius=0]  Corner rounding in px (0 = square),
 *                                   applied via the clipPath rect so
 *                                   fills and divider clip to the same
 *                                   shape.
 * @returns {{svg: string, width: number, height: number}}
 */
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
  cornerRadius = 0,
) {
  const layout = LAYOUT[style];
  const { labelTextX, labelWidth, messageTextX, messageWidth } = deriveGeometry(
    layout,
    label,
    message,
    showIcon,
  );
  const width = labelWidth + messageWidth;
  const height = layout.height;

  const iconGroup = showIcon
    ? `<g transform="translate(${layout.iconX} ${layout.iconY}) scale(${layout.iconScale})">
      <path d="${SYMBOL_PATH}" fill="${messageBg}"/>
    </g>`
    : "";

  const textAttrs = (x, fill) =>
    `x="${x}" y="${layout.textY}" fill="${fill}" font-family="${FONT_FAMILY}" font-size="${layout.fontSize}" font-weight="${layout.fontWeight}" text-rendering="geometricPrecision"`;

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="Glue: ${label} ${message}">
  <title>Glue: ${label} ${message}</title>
  <defs>
    <clipPath id="r">
      <rect width="${width}" height="${height}" rx="${cornerRadius}" fill="#fff"/>
    </clipPath>
  </defs>
  <g clip-path="url(#r)">
    <rect width="${labelWidth}" height="${height}" fill="${labelBg}"/>
    <rect x="${labelWidth}" width="${messageWidth}" height="${height}" fill="${messageBg}"/>
    <rect x="${labelWidth}" width="${layout.dividerWidth}" height="${height}" fill="${COLORS.divider}" opacity="0.65"/>
    ${iconGroup}
    <text ${textAttrs(labelTextX, labelColor || COLORS.text)}>${esc(label)}</text>
    <text ${textAttrs(messageTextX, messageColor || COLORS.surface)}>${esc(message)}</text>
  </g>
</svg>`;

  return { svg, width, height };
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
 * Shape variants generated for every (config × style). Square is the
 * default GitHub-readme look; rounded suits standalone marketing
 * placements. Corner radius is a pixel value applied to the clipPath
 * rect (so both fills and divider clip to the same shape).
 */
const VARIANTS = [
  { name: "square", cornerRadius: 0, filenameSuffix: "" },
  { name: "rounded", cornerRadius: 4, filenameSuffix: "-rounded" },
];

/**
 * Generate filename for a badge.
 * @param {Object} config
 * @param {string} style
 * @param {string} [variantSuffix=""]   e.g. `-rounded`; appended after style.
 * @returns {string}
 */
function filenameFor(
  { label, message, labelBg, messageBg },
  style,
  variantSuffix = "",
) {
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

  return `glue-${labelPrefix}${msgClean}-${style}${variantSuffix}-${labelBgSafe}-${msgBgSafe}`;
}

/**
 * Render one (config × style × variant) combination: writes both
 * `.svg` and `.png` to disk and returns the manifest entry.
 */
async function buildBadge(config, style, variant) {
  const fileBase = filenameFor(config, style, variant.filenameSuffix);
  const { svg, width, height } = generateSvg(
    config,
    style,
    variant.cornerRadius,
  );

  await writeFile(path.join(BADGES_DIR, `${fileBase}.svg`), svg, "utf-8");
  await writeFile(
    path.join(BADGES_DIR, `${fileBase}.png`),
    await renderPng(svg),
  );

  return {
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
    variant: variant.name,
    cornerRadius: variant.cornerRadius,
    width,
    height,
  };
}

async function main() {
  await mkdir(BADGES_DIR, { recursive: true });
  console.log("Generating badges...");

  const jsonBadges = [];
  for (const config of BADGE_CONFIGS) {
    for (const style of STYLES) {
      for (const variant of VARIANTS) {
        const entry = await buildBadge(config, style, variant);
        jsonBadges.push(entry);
        console.log(`  → ${entry.id}.svg + .png`);
      }
    }
  }

  await writeFile(
    path.join(BADGES_DIR, "badges.json"),
    JSON.stringify(jsonBadges, null, 2),
    "utf-8",
  );
  console.log("  → badges.json");

  console.log(
    `✓ generated ${jsonBadges.length} badges (${jsonBadges.length * 2} files) in public/badges/`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
