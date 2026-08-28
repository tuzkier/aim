/**
 * 从 iOS 的 asset catalog 生成对话面的颜色变量。
 *
 * 手抄一遍是行不通的：我第一版就是照截图估的色值，accent 偏亮、canvas 偏冷、
 * success 从橄榄变成了绿色，放在 App 里一眼就是「另一个应用」。而且抄一次之后
 * 原生改色，这边不会跟着变。
 *
 * 所以直接读那份唯一的真值。`make web-build` 会先跑它。
 */

import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const CATALOG = join(here, "../../ios/AimApp/Resources/Assets.xcassets/Aim");
const OUTPUT = join(here, "../src/tokens.css");

/** AimTextPrimary -> --aim-text-primary */
const toVariable = (name) =>
  `--${name.replace(/^Aim/, "aim-").replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase()}`;

const toByte = (raw) => {
  const text = String(raw).trim();
  if (text.startsWith("0x")) return Number.parseInt(text, 16);
  const value = Number.parseFloat(text);
  return Math.round(value <= 1 ? value * 255 : value);
};

const toHex = (components) =>
  "#" +
  ["red", "green", "blue"]
    .map((channel) => toByte(components[channel]).toString(16).padStart(2, "0"))
    .join("");

const light = [];
const dark = [];

for (const entry of readdirSync(CATALOG).sort()) {
  if (!entry.endsWith(".colorset")) continue;
  const name = entry.replace(/\.colorset$/, "");
  const contents = JSON.parse(readFileSync(join(CATALOG, entry, "Contents.json"), "utf8"));
  for (const color of contents.colors ?? []) {
    const components = color.color?.components;
    if (!components) continue;
    const isDark = (color.appearances ?? []).some((a) => a.value === "dark");
    (isDark ? dark : light).push(`  ${toVariable(name)}: ${toHex(components)};`);
  }
}

const css = `/* 由 scripts/sync-tokens.mjs 从 iOS 的 asset catalog 生成，不要手改。
   原生改色之后重新跑 make web-build 即可，两边不会再漂移。 */
:root {
${light.join("\n")}
}

.app--dark {
${dark.join("\n")}
}
`;

writeFileSync(OUTPUT, css);
console.log(`tokens.css 已生成：${light.length} 个浅色、${dark.length} 个深色`);
