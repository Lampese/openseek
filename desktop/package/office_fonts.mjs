import { existsSync } from "node:fs";
import { join } from "node:path";

export const OfficeFontFiles = [
  "Carlito-Regular.ttf",
  "Carlito-Bold.ttf",
  "Carlito-Italic.ttf",
  "Carlito-BoldItalic.ttf",
  "LiberationSans-Regular.ttf",
  "LiberationSans-Bold.ttf",
  "LiberationSans-Italic.ttf",
  "LiberationSans-BoldItalic.ttf",
  "LiberationSerif-Regular.ttf",
  "LiberationSerif-Bold.ttf",
  "LiberationSerif-Italic.ttf",
  "LiberationSerif-BoldItalic.ttf",
  "LiberationMono-Regular.ttf",
  "LiberationMono-Bold.ttf",
  "LiberationMono-Italic.ttf",
  "LiberationMono-BoldItalic.ttf",
  "NotoSansSC-Regular.ttf",
  "LICENSES/Carlito-OFL.txt",
  "LICENSES/Liberation-LICENSE.txt",
  "LICENSES/NotoSansSC-OFL.txt",
];

export function resolveOfficeFontSource(candidates, exists = existsSync) {
  const source = candidates.find(candidate =>
    OfficeFontFiles.every(name => exists(join(candidate, name))));
  if (!source) {
    throw new Error(
      "Office viewer fonts are missing; resolve the Mooncakes dependency " +
      "or desktop/package/assets/fonts.",
    );
  }
  return source;
}
