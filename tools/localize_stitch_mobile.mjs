import { createHash } from 'node:crypto';
import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const exportDir = resolve(scriptDir, process.argv[2] ?? '../design/stitch-mobile');
const assetsDir = join(exportDir, 'assets');
const hostedUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const assets = new Map();

function normalizeUrl(value) {
  return value.replaceAll('&amp;', '&').trim();
}

function extensionFor(url, contentType) {
  const fromUrl = extname(new URL(url).pathname).toLowerCase();
  if (fromUrl && fromUrl.length <= 6) return fromUrl;
  const mime = contentType.split(';', 1)[0].trim().toLowerCase();
  const extensions = new Map([
    ['text/css', '.css'],
    ['text/javascript', '.js'],
    ['application/javascript', '.js'],
    ['application/x-javascript', '.js'],
    ['font/woff2', '.woff2'],
    ['font/woff', '.woff'],
    ['font/ttf', '.ttf'],
    ['image/avif', '.avif'],
    ['image/gif', '.gif'],
    ['image/jpeg', '.jpg'],
    ['image/png', '.png'],
    ['image/svg+xml', '.svg'],
    ['image/webp', '.webp'],
  ]);
  return extensions.get(mime) ?? '.bin';
}

function assetPathFor(url, contentType) {
  const hash = createHash('sha256').update(url).digest('hex').slice(0, 16);
  return `${hash}${extensionFor(url, contentType)}`;
}

async function getResource(url) {
  const normalized = normalizeUrl(url);
  const existing = assets.get(normalized);
  if (existing) return existing;

  const response = await fetch(normalized, {
    headers: { 'user-agent': hostedUserAgent },
    redirect: 'follow',
  });
  if (!response.ok) throw new Error(`Resource download failed (${response.status}): ${normalized}`);

  const contentType = response.headers.get('content-type') ?? 'application/octet-stream';
  const file = assetPathFor(normalized, contentType);
  const record = { url: normalized, file, contentType, bytes: 0 };
  assets.set(normalized, record);

  let content = Buffer.from(await response.arrayBuffer());
  if (contentType.toLowerCase().includes('text/css')) {
    let css = content.toString('utf8');
    const references = [...css.matchAll(/url\(\s*(['"]?)(https?:\/\/[^\s'")]+)\1\s*\)/gi)];
    for (const match of references) {
      const child = await getResource(match[2]);
      css = css.replaceAll(match[0], `url("./${child.file}")`);
    }
    content = Buffer.from(css);
  }

  record.bytes = content.byteLength;
  await writeFile(join(assetsDir, file), content);
  return record;
}

function urlsIn(value) {
  return [...new Set([...value.matchAll(/https?:\/\/[^\s'"<>`)]+/g)].map((match) => normalizeUrl(match[0])))];
}

function relativeAsset(fromDir, file) {
  return relative(fromDir, join(assetsDir, file)).split(sep).join('/');
}

await mkdir(assetsDir, { recursive: true });
const screenDirs = (await readdir(exportDir, { withFileTypes: true }))
  .filter((entry) => entry.isDirectory() && entry.name !== 'assets')
  .map((entry) => join(exportDir, entry.name));

if (screenDirs.length === 0) throw new Error(`No screen directories found under ${exportDir}`);

const screenSources = [];
for (const screenDir of screenDirs) {
  const hostedPath = join(screenDir, 'hosted.html');
  const indexPath = join(screenDir, 'index.html');
  const sourcePath = await readFile(hostedPath).then(() => hostedPath, async () => {
    await copyFile(indexPath, hostedPath);
    return hostedPath;
  });
  screenSources.push({ screenDir, source: await readFile(sourcePath, 'utf8') });
}

for (const { source } of screenSources) {
  for (const url of urlsIn(source)) {
    const parsed = new URL(url);
    if ((parsed.hostname === 'fonts.googleapis.com' || parsed.hostname === 'fonts.gstatic.com') && parsed.pathname === '/') continue;
    await getResource(url);
  }
}

for (const { screenDir, source } of screenSources) {
  let localized = source.replace(/<link\b[^>]*>/gi, (tag) =>
    /\brel\s*=\s*(['"]?)preconnect\1/i.test(tag) ? '' : tag,
  );
  for (const url of urlsIn(source)) {
    const record = assets.get(url);
    if (!record) continue;
    const localPath = relativeAsset(screenDir, record.file);
    localized = localized.replaceAll(url.replaceAll('&', '&amp;'), localPath);
    localized = localized.replaceAll(url, localPath);
  }
  await writeFile(join(screenDir, 'index.html'), localized);
}

const manifest = [...assets.values()].sort((a, b) => a.file.localeCompare(b.file));
await writeFile(join(assetsDir, 'manifest.json'), `${JSON.stringify({ assets: manifest }, null, 2)}\n`);
console.log(`Localized ${screenDirs.length} screens with ${manifest.length} shared assets in ${assetsDir}`);
