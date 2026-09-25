// Usage: node tools/scripts/stamp-spm-release.mjs <version> <checksum>
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const [version, checksum] = process.argv.slice(2);
if (!version || !checksum) {
  console.error('Usage: node tools/scripts/stamp-spm-release.mjs <version> <checksum>');
  process.exit(1);
}
if (!/^\d+\.\d+\.\d+(-[\w.]+)?$/.test(version)) {
  console.error(`error: "${version}" is not a valid semver version`);
  process.exit(1);
}
if (!/^[0-9a-f]{64}$/.test(checksum)) {
  console.error(`error: "${checksum}" is not a valid SHA-256 checksum`);
  process.exit(1);
}

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

function stamp(file, replacements) {
  const path = resolve(repoRoot, file);
  let content = readFileSync(path, 'utf8');
  for (const [pattern, replacement] of replacements) {
    if (!pattern.test(content)) {
      console.error(`error: ${file} does not match ${pattern}`);
      process.exit(1);
    }
    content = content.replace(pattern, replacement);
  }
  writeFileSync(path, content);
}

stamp('Package.swift', [
  [
    /releases\/download\/[^/]+\/FontManager\.xcframework\.zip/,
    `releases/download/${version}/FontManager.xcframework.zip`,
  ],
  [/checksum: "[^"]*"/, `checksum: "${checksum}"`],
]);

stamp('packages/font-manager/nativescript.config.ts', [
  [/version: '[^']*'/, `version: '${version}'`],
]);
