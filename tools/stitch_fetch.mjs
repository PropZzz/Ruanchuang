import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { join } from 'node:path';
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
const screens = await project.screens();
const byId = new Map(screens.map((screen) => [screen.id, screen]));
const manifest = [];

await mkdir(join(outputDir, 'screens'), { recursive: true });

for (const [screenId, slug, title] of requestedScreens) {
  const screen = byId.get(screenId) ?? await project.getScreen(screenId);
  if (!screen) throw new Error(`Screen not found: ${screenId}`);
  const htmlUrl = await screen.getHtml();
  const imageUrl = await screen.getImage();
  const screenDir = join(outputDir, 'screens', slug);
  await mkdir(screenDir, { recursive: true });
  const [htmlResponse, imageResponse] = await Promise.all([
    fetch(htmlUrl),
    fetch(imageUrl),
  ]);
  if (!htmlResponse.ok) throw new Error(`HTML download failed for ${screenId}: ${htmlResponse.status}`);
  if (!imageResponse.ok) throw new Error(`Image download failed for ${screenId}: ${imageResponse.status}`);
  await writeFile(join(screenDir, 'index.html'), await htmlResponse.text());
  const imageType = imageResponse.headers.get('content-type') ?? 'image/png';
  const extension = imageType.includes('jpeg') || imageType.includes('jpg') ? 'jpg' : imageType.includes('webp') ? 'webp' : 'png';
  const imageFile = `screenshot.${extension}`;
  await writeFile(join(screenDir, imageFile), Buffer.from(await imageResponse.arrayBuffer()));
  manifest.push({
    id: screenId,
    slug,
    title,
    name: screen.name ?? null,
    htmlUrl,
    imageUrl,
    htmlFile: `screens/${slug}/index.html`,
    imageFile: `screens/${slug}/${imageFile}`,
  });
  console.log(`${slug}: downloaded`);
}

await writeFile(join(outputDir, 'manifest.json'), JSON.stringify({ projectId, screens: manifest }, null, 2) + '\n');
console.log(`Saved ${manifest.length} screens to ${outputDir}`);
