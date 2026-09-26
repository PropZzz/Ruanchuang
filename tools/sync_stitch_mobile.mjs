import { cp, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const sourceRoot = resolve(root, 'design/stitch-mobile');
const targetRoot = resolve(root, 'web/stitch/mobile');
const checkOnly = process.argv.includes('--check');

async function sameFile(source, target) {
  try {
    const [left, right] = await Promise.all([readFile(source), readFile(target)]);
    return left.equals(right);
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

async function sameHtml(source, target) {
  try {
    const [left, right] = await Promise.all([
      readFile(source, 'utf8'),
      readFile(target, 'utf8'),
    ]);
    return left.replace(/[ \t]+$/gm, '') === right.replace(/[ \t]+$/gm, '');
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

async function copyOrCheck(source, target) {
  if (checkOnly) return sameFile(source, target);
  await mkdir(dirname(target), { recursive: true });
  await cp(source, target, { force: true });
  return true;
}

const entries = await readdir(sourceRoot, { withFileTypes: true });
const screens = entries.filter((entry) => entry.isDirectory() && entry.name !== 'assets');
if (screens.length === 0) throw new Error(`No Stitch mobile screens found in ${sourceRoot}`);

let synchronized = true;
for (const screen of screens) {
  const source = join(sourceRoot, screen.name, 'index.html');
  const target = join(targetRoot, screen.name, 'index.html');
  if (checkOnly) {
    synchronized = (await sameHtml(source, target)) && synchronized;
  } else {
    const content = (await readFile(source, 'utf8')).replace(/[ \t]+$/gm, '');
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, content);
  }
}

const sourceAssets = join(sourceRoot, 'assets');
const targetAssets = join(targetRoot, 'assets');
if (checkOnly) {
  const assetEntries = await readdir(sourceAssets);
  for (const asset of assetEntries) {
    const source = join(sourceAssets, asset);
    if ((await stat(source)).isFile()) {
      synchronized = (await sameFile(source, join(targetAssets, asset))) && synchronized;
    }
  }
} else {
  await cp(sourceAssets, targetAssets, { recursive: true, force: true });
  await cp(join(sourceRoot, 'assets', 'polish.css'), join(root, 'web/stitch/mobile/assets/polish.css'), { force: true });
}

if (checkOnly) {
  if (!synchronized) {
    console.error('Stitch mobile deployment files are out of sync with design/stitch-mobile.');
    process.exitCode = 1;
  } else {
    console.log(`Stitch mobile deployment is synchronized (${screens.length} screens).`);
  }
} else {
  console.log(`Synchronized ${screens.length} Stitch mobile screens from design/stitch-mobile.`);
}
