import { mkdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { stitch } from '@google/stitch-sdk';

const projectId = '2037391297990000917';
const outputDir = process.argv[2] ?? 'stitch';

const requestedScreens = [
  ['103e9cc49f7c41ae8a7033c5f941322f', 'smart-calendar', '智能日历核心工作台'],
  ['5096e8843b104fc8bcefdb95b6192be5', 'rescue-comparison', '紧急任务三方案救援比较'],
  ['7de8368b293749c0ab5bc5bfb802bb75', 'focus', '专注 Focus'],
  ['ce58f38674a14dafb39cc9ba469e0dc4', 'team', '团队 Team'],
  ['c529c8cd69854a0eb5357eff5deac03c', 'microtasks', '微任务 Microtasks'],
  ['1623975f700f4227be2fc1cdcec663a3', 'profile', '我的 Profile'],
  ['286623cdc28f41a8997a1288a8dbc4e0', 'goals', '目标与执行分解 Goals'],
  ['43d2faea5a904c35b39f65a83c7fd703', 'review', '智能复盘与调度审计 Review'],
  ['fa721a17b50b4b1c8bbd1bf8d199cf9b', 'integrations', 'MCP 接入与智能解析 Integrations'],
  ['366e02e8368f474eb62f0328f2b206d9', 'settings-drawer', '设置抽屉与系统偏好 Settings Drawer'],
  ['d86aa9d3733c410083bb1f2929cf6640', 'bluetooth', '蓝牙设备与传感器 Bluetooth'],
  ['9eef5f7ba36c4b6295dbe69f17231967', 'emotion-energy', '情绪与能量 Emotion & Energy'],
  ['ddffac1354d14106b5ae99f206099cb6', 'diagnostics', '系统诊断 Diagnostics'],
];

if (!process.env.STITCH_API_KEY && !process.env.STITCH_ACCESS_TOKEN) {
  throw new Error('Set STITCH_API_KEY or STITCH_ACCESS_TOKEN before running.');
}

const project = stitch.project(projectId);
const screenList = await project.screens();
const byId = new Map(screenList.map((screen) => [screen.id, screen]));
const manifest = [];

await mkdir(join(outputDir, 'screens'), { recursive: true });
await rm(join(outputDir, 'assets'), { recursive: true, force: true });

const decodeEntities = (value) => value
  .replaceAll('&amp;', '&')
  .replaceAll('&#x2F;', '/')
  .replaceAll('&#47;', '/');

const hash = (value) => createHash('sha1').update(value).digest('hex').slice(0, 12);

const extensionFor = (contentType, url, fallback) => {
  const mime = contentType.split(';')[0].toLowerCase();
  const mimeExtensions = new Map([
    ['text/css', 'css'],
    ['text/javascript', 'js'],
    ['application/javascript', 'js'],
    ['application/x-javascript', 'js'],
    ['image/png', 'png'],
    ['image/jpeg', 'jpg'],
    ['image/webp', 'webp'],
    ['image/gif', 'gif'],
    ['font/woff2', 'woff2'],
    ['font/woff', 'woff'],
    ['application/font-woff', 'woff'],
    ['application/octet-stream', fallback],
  ]);
  if (mimeExtensions.has(mime)) return mimeExtensions.get(mime);
  const pathname = new URL(url).pathname;
  const match = pathname.match(/\.([a-z0-9]+)$/i);
  return match?.[1]?.toLowerCase() ?? fallback;
};

const assetUrlPattern = /https?:\/\/[^\s"'<>\)]+/g;

async function fetchAsset(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Asset download failed (${response.status}): ${url}`);
  return {
    contentType: response.headers.get('content-type') ?? 'application/octet-stream',
    body: Buffer.from(await response.arrayBuffer()),
  };
}

async function localizeHtml(hostedHtml, screenDir) {
  const assetRoot = join(outputDir, 'assets');
  const relativeAssetRoot = '../../assets';
  const assetDirs = {
    images: join(assetRoot, 'images'),
    fonts: join(assetRoot, 'fonts'),
    vendor: join(assetRoot, 'vendor'),
  };
  await Promise.all(Object.values(assetDirs).map((directory) => mkdir(directory, { recursive: true })));
  const assets = [];
  const replacements = new Map();

  const save = async (url, category, fallbackExtension, contents, contentType) => {
    const extension = extensionFor(contentType, url, fallbackExtension);
    const filename = `${hash(url)}.${extension}`;
    const relative = `${relativeAssetRoot}/${category}/${filename}`;
    await writeFile(join(assetRoot, category, filename), contents);
    assets.push({ url, localPath: relative, contentType, bytes: contents.length });
    replacements.set(url, relative);
    return relative;
  };

  const externalUrls = [...new Set((hostedHtml.match(assetUrlPattern) ?? []).map(decodeEntities))];
  for (const url of externalUrls) {
    if (url.startsWith('https://fonts.googleapis.com/css')) {
      const css = await fetchAsset(url);
      let cssText = css.body.toString('utf8');
      const cssUrls = [...new Set((cssText.match(assetUrlPattern) ?? []).map(decodeEntities))];
      for (const fontUrl of cssUrls) {
        if (!fontUrl.startsWith('https://fonts.gstatic.com/')) continue;
        const font = await fetchAsset(fontUrl);
        const localFont = await save(fontUrl, 'fonts', 'bin', font.body, font.contentType);
        cssText = cssText.split(fontUrl).join(localFont.split('/').pop());
      }
      const localCss = await save(url, 'fonts', 'css', Buffer.from(cssText), 'text/css');
      replacements.set(url, localCss);
      continue;
    }
    if (url === 'https://cdn.tailwindcss.com') {
      const script = await fetchAsset(url);
      await save(url, 'vendor', 'js', script.body, script.contentType);
      continue;
    }
    if (url.startsWith('https://lh3.googleusercontent.com/') || url.startsWith('https://lh4.googleusercontent.com/') || url.startsWith('https://lh5.googleusercontent.com/') || url.startsWith('https://lh6.googleusercontent.com/')) {
      const image = await fetchAsset(url);
      await save(url, 'images', 'bin', image.body, image.contentType);
    }
  }

  let localizedHtml = hostedHtml;
  for (const [url, localPath] of replacements) {
    localizedHtml = localizedHtml.split(url).join(localPath);
    localizedHtml = localizedHtml.split(url.replaceAll('&', '&amp;')).join(localPath);
  }
  localizedHtml = localizedHtml.replace(/<link[^>]+rel=["']preconnect["'][^>]*>/gi, '');
  await writeFile(join(screenDir, 'asset-manifest.json'), JSON.stringify({ assets }, null, 2) + '\n');
  return { html: localizedHtml, assets };
}

for (const [screenId, slug, title] of requestedScreens) {
  const screen = byId.get(screenId);
  if (!screen) throw new Error(`Screen not found: ${screenId}`);
  const htmlUrl = await screen.getHtml();
  const imageUrl = await screen.getImage();
  const screenDir = join(outputDir, 'screens', slug);
  await mkdir(screenDir, { recursive: true });
  await rm(join(screenDir, 'assets'), { recursive: true, force: true });
  const [htmlResponse, imageResponse] = await Promise.all([fetch(htmlUrl), fetch(imageUrl)]);
  if (!htmlResponse.ok) throw new Error(`HTML download failed for ${screenId}: ${htmlResponse.status}`);
  if (!imageResponse.ok) throw new Error(`Image download failed for ${screenId}: ${imageResponse.status}`);
  const hostedHtml = await htmlResponse.text();
  await writeFile(join(screenDir, 'hosted.html'), hostedHtml);
  const { html: localizedHtml } = await localizeHtml(hostedHtml, screenDir);
  await writeFile(join(screenDir, 'index.html'), localizedHtml);
  await writeFile(join(screenDir, 'screen.json'), JSON.stringify({
    ...(screen.data ?? {}),
    id: screen.id,
    projectId,
    title,
  }, null, 2) + '\n');
  const imageType = imageResponse.headers.get('content-type') ?? 'image/png';
  const extension = imageType.includes('jpeg') || imageType.includes('jpg') ? 'jpg' : imageType.includes('webp') ? 'webp' : 'png';
  const imageFile = `screenshot.${extension}`;
  await writeFile(join(screenDir, imageFile), Buffer.from(await imageResponse.arrayBuffer()));
  manifest.push({
    id: screenId,
    slug,
    title,
    name: screen.data?.name ?? null,
    htmlUrl,
    imageUrl,
    hostedHtmlFile: `screens/${slug}/hosted.html`,
    localizedHtmlFile: `screens/${slug}/index.html`,
    screenJsonFile: `screens/${slug}/screen.json`,
    assetManifestFile: `screens/${slug}/asset-manifest.json`,
    htmlFile: `screens/${slug}/index.html`,
    imageFile: `screens/${slug}/${imageFile}`,
  });
  console.log(`${slug}: downloaded`);
}

await writeFile(join(outputDir, 'manifest.json'), JSON.stringify({ projectId, screens: manifest }, null, 2) + '\n');
console.log(`Saved ${manifest.length} screens to ${outputDir}`);
