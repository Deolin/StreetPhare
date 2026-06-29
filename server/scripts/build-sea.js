// server/scripts/build-sea.js
// Build Node.js Single Executable Application (SEA) — remplace pkg.
//
// Usage : node scripts/build-sea.js primary|backup
//
// Étapes :
//   1. Bundle le point d'entrée avec esbuild (API programmatique, CommonJS).
//   2. Génère le blob SEA via node --experimental-sea-config.
//   3. Copie l'exécutable Node.js courant et injecte le blob via postject.
//
// Prérequis : Node.js ≥ 21, esbuild en devDependencies.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const target = process.argv[2];
if (!['primary', 'backup'].includes(target)) {
  console.error('Usage: node scripts/build-sea.js primary|backup');
  process.exit(1);
}

const root = path.resolve(__dirname, '..');
const distDir = path.join(root, 'dist');
const buildDir = path.join(root, 'build');
const entryFile = path.join(root, 'src', `${target}.js`);
const bundleFile = path.join(distDir, `${target}.bundle.cjs`);

// Résolution d'esbuild : peut être dans server/node_modules ou hoisté à la racine workspace.
function resolveEsbuild() {
  const candidates = [
    path.join(root, 'node_modules', 'esbuild'),
    path.join(root, '..', 'node_modules', 'esbuild'),
  ];
  for (const c of candidates) {
    try {
      return require(path.join(c, 'lib', 'main'));
    } catch (_) {}
  }
  console.error('[SEA] esbuild not found. Run `npm install` first.');
  process.exit(1);
}

const esbuild = resolveEsbuild();

(async () => {
  // ── Étape 1 : Bundle CommonJS avec esbuild ─────────────────────────
  console.log(`[SEA] Bundling ${target} → ${bundleFile} ...`);
  fs.mkdirSync(distDir, { recursive: true });

  try {
    await esbuild.build({
      entryPoints: [entryFile],
      bundle: true,
      platform: 'node',
      format: 'cjs',
      outfile: bundleFile,
      minify: false, // SEA nécessite un bundle lisible
    });
  } catch (e) {
    console.error('[SEA] esbuild failed:', e.message || e);
    process.exit(1);
  }

  // ── Étape 2 : Génération du blob SEA ──────────────────────────────
  const configFile = path.join(root, `sea-config-${target}.json`);
  console.log(`[SEA] Generating blob for ${target} ...`);
  try {
    execSync(`node --experimental-sea-config "${configFile}"`, {
      cwd: root,
      stdio: 'inherit',
    });
  } catch (e) {
    console.error('[SEA] Blob generation failed.');
    process.exit(1);
  }

  // ── Étape 3 : Copie et injection ──────────────────────────────────
  const exeName = `streetphare-${target}.exe`;
  const exePath = path.join(buildDir, exeName);
  const blobPath = path.join(distDir, `sea-prep-${target}.blob`);

  fs.mkdirSync(buildDir, { recursive: true });

  // Suppression d'un ancien build si présent
  try {
    if (fs.existsSync(exePath)) fs.unlinkSync(exePath);
  } catch (_) {}

  console.log(`[SEA] Copying node binary → ${exePath} ...`);
  fs.copyFileSync(process.execPath, exePath);

  console.log("[SEA] Removal of original signature...");
  try {
      // Supprime toutes les signatures du binaire copié
      const signtool = process.env.SIGNTOOL || 'signtool';
      execSync(`"${signtool}" remove /s "${exePath}"`);
  } catch (err) {
      console.log("Signtool non trouvé ou inutile, tentative alternative...");
  }
  // Injection du blob via postject.
  console.log(`[SEA] Injecting blob into ${exeName} ...`);
  try {
    execSync(
      `npx --yes postject "${exePath}" NODE_SEA_BLOB "${blobPath}" ` +
      `--sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2`,
      { cwd: root, stdio: 'inherit' }
    );
  } catch (e) {
    console.error('[SEA] postject injection failed.');
    process.exit(1);
  }

  console.log(`[SEA] Build complete: ${exePath}`);
})().catch((e) => {
  console.error('[SEA] Unexpected error:', e);
  process.exit(1);
});