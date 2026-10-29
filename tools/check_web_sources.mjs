import assert from 'node:assert/strict';
import { readFile, readdir, stat } from 'node:fs/promises';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const projectRoot = fileURLToPath(new URL('..', import.meta.url));

export async function checkWebSources(root = projectRoot) {
  const web = resolve(root, 'web');
  let references = 0;
  let pages = 0;
  const files = [];
  async function walk(folder) {
    for (const entry of await readdir(folder, { withFileTypes: true })) {
      const file = join(folder, entry.name);
      if (entry.isDirectory()) await walk(file);
      else if (entry.isFile()) files.push(file);
    }
  }
  async function check(file, reference) {
    const url = reference.trim().replaceAll('&amp;', '&');
    if (!url || /^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(url)) return;
    const pathname = decodeURIComponent(url.split(/[?#]/)[0]);
    if (!pathname) return;
    const target = pathname.startsWith('/') ? resolve(web, '.' + pathname) : resolve(dirname(file), pathname);
    assert.ok(target.startsWith(web + sep), `${relative(root, file)} escapes web/: ${url}`);
    assert.ok((await stat(target).catch(() => null))?.isFile(), `${relative(root, file)} missing asset: ${url}`);
    references++;
  }
  await walk(web);
  const index = await readFile(join(web, 'index.html'), 'utf8');
  assert.ok(index.includes('src="stitch/router.js"'), 'web/index.html must load the canonical router');
  assert.ok(index.includes('src="stitch/page-host.js"'), 'web/index.html must load the persistent page host');
  const router = await readFile(join(web, 'stitch/router.js'), 'utf8');
  const routes = router.match(/const pages = \{([\s\S]*?)\n  \};/)?.[1];
  assert.ok(routes, 'Cannot find the router page map');
  for (const match of routes.matchAll(/['"]((?:screens|mobile|components)\/[^'"]+\.html)['"]/g)) {
    await check(join(web, 'stitch/router.js'), match[1]);
    pages++;
  }
  assert.ok(pages > 0, 'The router must contain pages');
  for (const file of files) {
    if (!['.html', '.css'].includes(extname(file))) continue;
    const source = await readFile(file, 'utf8');
    if (extname(file) === '.html') {
      for (const tag of source.matchAll(/<(?:script|img|link|iframe|source|video|audio)\b[^>]*>/gi)) {
        for (const attribute of tag[0].matchAll(/\s(?:src|href|poster)\s*=\s*["']([^"']*)["']/gi)) {
          await check(file, attribute[1]);
        }
      }
    }
    for (const match of source.matchAll(/url\(\s*["']?([^\s)'"<>]+)["']?\s*\)/gi)) await check(file, match[1]);
  }
  const pubspec = await readFile(join(root, 'pubspec.yaml'), 'utf8');
  let nativeAssets = 0;
  for (const match of pubspec.matchAll(/^\s+-\s+(?:asset:\s*)?((?:assets|stitch\/assets)\/[^\r\n]+)\s*$/gm)) {
    const path = match[1].trim();
    assert.ok(await stat(join(root, path)).catch(() => null), `Missing Flutter asset: ${path}`);
    nativeAssets++;
  }
  return { webFiles: files.length, routePages: pages, localReferences: references, nativeAssetDeclarations: nativeAssets };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    console.log(JSON.stringify(await checkWebSources(), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
