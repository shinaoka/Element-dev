#!/usr/bin/env node
/**
 * Remove @types/node from png-to-ico's runtime dependencies.
 * electron-builder 26+ traverses production deps; png-to-ico incorrectly lists @types/node there.
 * Invoked from Element-dev build-local-exe.ps1 so element-web stays unpatched.
 */
const fs = require("fs");
const path = require("path");

const elementWebRoot = process.argv[2];
if (!elementWebRoot) {
    console.error("usage: node electron-builder-fix-png-to-ico.js <element-web-root>");
    process.exit(1);
}

const candidates = [
    path.join(elementWebRoot, "node_modules", "png-to-ico", "package.json"),
    path.join(elementWebRoot, "apps", "desktop", "node_modules", "png-to-ico", "package.json"),
];

for (const pkgPath of candidates) {
    if (!fs.existsSync(pkgPath)) continue;
    const j = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    if (!j.dependencies || !Object.prototype.hasOwnProperty.call(j.dependencies, "@types/node")) {
        continue;
    }
    delete j.dependencies["@types/node"];
    fs.writeFileSync(pkgPath, JSON.stringify(j, null, 2) + "\n");
    console.log("patched:", pkgPath);
}
