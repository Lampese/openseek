import assert from "node:assert/strict";
import test from "node:test";
import { OfficeFontFiles, resolveOfficeFontSource } from "./office_fonts.mjs";

test("Office fonts prefer the sibling viewer and fall back to checked-in assets", () => {
  const complete = new Set(OfficeFontFiles.map(name => `/fallback/${name}`));
  const exists = path => complete.has(path) || path.startsWith("/sibling/");
  assert.equal(
    resolveOfficeFontSource(["/sibling", "/fallback"], exists),
    "/sibling",
  );
  assert.equal(
    resolveOfficeFontSource(["/missing", "/fallback"], exists),
    "/fallback",
  );
  assert.throws(
    () => resolveOfficeFontSource(["/missing"], () => false),
    /Office viewer fonts are missing/,
  );
});
