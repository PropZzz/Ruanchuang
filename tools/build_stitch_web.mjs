import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const projectRoot = fileURLToPath(new URL('..', import.meta.url));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

async function sourceFiles(root, prefix = '') {
  const files = [];
  for (const entry of (await readdir(join(root, prefix), { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name, 'en'))) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) files.push(...await sourceFiles(root, relative));
    else if (entry.isFile()) files.push(relative);
    else throw new Error(`Unsupported web source: ${relative}`);
  }
  return files;
}

export async function buildStitchWeb({
  sourceRoot = join(projectRoot, 'web'),
  outputRoot = join(projectRoot, 'build/stitch-web'),
} = {}) {
  // Read once: the manifest and copied bytes describe the same source snapshot.
  const contents = new Map();
  for (const file of await sourceFiles(sourceRoot)) {
    contents.set(file, await readFile(join(sourceRoot, file)));
  }
  const sourceHashes = Object.fromEntries([...contents].map(([file, bytes]) => [file, sha256(bytes)]));
  const release = sha256(JSON.stringify(sourceHashes)).slice(0, 16);
  const output = resolve(outputRoot, release);
  const index = contents.get('index.html')?.toString('utf8');
  const router = contents.get('stitch/router.js');
  if (!index?.includes('src="stitch/router.js"') || !router) {
    throw new Error('Expected the canonical Stitch web/index.html and web/stitch/router.js.');
  }
  const routerPath = `stitch/router.${release}.js`;
  contents.set(routerPath, router);
  contents.set('index.html', Buffer.from(index.replace(
    'src="stitch/router.js"',
    `src="${routerPath}" data-release="${release}"`,
  )));
  if (index.includes('src="stitch/page-host.js"')) {
    const hostPath = `stitch/page-host.${release}.js`;
    contents.set(hostPath, contents.get('stitch/page-host.js'));
    contents.set('index.html', Buffer.from(contents.get('index.html').toString('utf8').replace(
      'src="stitch/page-host.js"', `src="${hostPath}"`,
    )));
  }
  if (index.includes('src="stitch/drawer-motion.js"')) {
    const motionPath = `stitch/drawer-motion.${release}.js`;
    contents.set(motionPath, contents.get('stitch/drawer-motion.js'));
    contents.set('index.html', Buffer.from(contents.get('index.html').toString('utf8').replace(
      'src="stitch/drawer-motion.js"', `src="${motionPath}"`,
    )));
  }
  const files = {};
  if (index.includes('src="stitch/actions.js"')) {
    const actionsPath = `stitch/actions.${release}.js`;
    contents.set(actionsPath, contents.get('stitch/actions.js'));
    contents.set('index.html', Buffer.from(contents.get('index.html').toString('utf8').replace(
      'src="stitch/actions.js"', `src="${actionsPath}"`,
    )));
  }
  if (index.includes('src="stitch/calendar.js"')) {
    const calendarPath = `stitch/calendar.${release}.js`;
    contents.set(calendarPath, contents.get('stitch/calendar.js'));
    contents.set('index.html', Buffer.from(contents.get('index.html').toString('utf8').replace(
      'src="stitch/calendar.js"', `src="${calendarPath}"`,
    )));
  }
  for (const [file, bytes] of contents) {
    await mkdir(dirname(join(output, file)), { recursive: true });
    await writeFile(join(output, file), bytes);
    files[file] = sha256(bytes);
  }
  const manifest = { release, router: routerPath, files };
  await writeFile(join(output, 'release.json'), JSON.stringify(manifest, null, 2) + '\n');
  return { output, ...manifest };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const sourceArgument = process.argv.indexOf('--source-root');
  const { output, release, router } = await buildStitchWeb(sourceArgument < 0 ? {} : { sourceRoot: resolve(process.argv[sourceArgument + 1]) });
  console.log(JSON.stringify({ output, release, router }, null, 2));
}
