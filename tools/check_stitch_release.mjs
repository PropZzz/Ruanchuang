import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { dirname, extname, join, resolve, sep } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { buildStitchWeb } from './build_stitch_web.mjs';

// Use an installed Playwright runtime; no project dependency is required.
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('..', import.meta.url));
const release = await buildStitchWeb();
const sourceRouter = await readFile(join(root, 'web/stitch/router.js'), 'utf8');
const legacyRouter = sourceRouter
  .replace('syncSidebarNavigation(childDocument, pageRoute);', '')
  .replace(' && !pageHost.primary.has(pageRoute)', '')
  .replace('const parentRoutes = {', "const parentRoutes = { review: 'profile', diagnostics: 'profile',");
const sourceIndex = await readFile(join(root, 'web/index.html'), 'utf8');
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.json': 'application/json' };
let phase = 'legacy';
let routerRequests = 0;
let legacyWorker = false;
const server = createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  try {
    let body;
    if (pathname === '/flutter_service_worker.js' && legacyWorker) {
      body = `
        self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
        self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
        self.addEventListener('fetch', event => {
          if (new URL(event.request.url).pathname === '/stitch/router.js') {
            event.respondWith(caches.open('flutter-app-cache').then(async cache =>
              (await cache.match(event.request)) || fetch(event.request)));
          }
        });`;
    } else if (pathname.startsWith('/api/')) {
      body = '{}';
    } else if (pathname === '/stitch/router.js') {
      routerRequests++;
      body = phase === 'legacy' ? legacyRouter : sourceRouter;
    } else if (pathname === '/' && phase !== 'release') {
      body = sourceIndex;
    } else {
      const folder = phase === 'release' ? release.output : join(root, 'web');
      const target = resolve(folder, '.' + (pathname === '/' ? '/index.html' : pathname));
      if (!target.startsWith(folder + sep)) throw new Error('Outside web root');
      body = await readFile(target);
    }
    response.writeHead(200, {
      'Content-Type': mime[extname(pathname)] || (pathname === '/' ? 'text/html' : 'application/json'),
      // Reproduce a browser keeping the previously published, unversioned JS.
      'Cache-Control': pathname === '/stitch/router.js' ? 'public, max-age=31536000' : 'no-store',
    });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const localUrl = `http://127.0.0.1:${server.address().port}/`;
const urlIndex = process.argv.indexOf('--url');
const deployedUrl = urlIndex >= 0 ? process.argv[urlIndex + 1] : null;
const browser = await chromium.launch({ headless: true });

async function sidebar(page, route, fixed) {
  await page.waitForFunction(route => {
    const frame = document.getElementById('prototype-screen');
    return frame?.title === `时序智配 ${route}` && !frame.classList.contains('route-switching') && frame.contentDocument?.querySelector('aside nav');
  }, route);
  const state = await page.locator('#prototype-screen').evaluate(frame => ({
    selected: [...frame.contentDocument.querySelectorAll('aside nav a[aria-current="page"]')].map(a => a.dataset.path),
    highlighted: [...frame.contentDocument.querySelectorAll('aside nav a.bg-primary-container')].map(a => a.dataset.path),
    back: !!frame.contentDocument.querySelector('[data-router-back]'),
  }));
  assert.deepEqual(state, fixed
    ? { selected: [route], highlighted: [route], back: false }
    : { selected: [], highlighted: [], back: true });
  console.log(`${fixed ? 'Fixed' : 'Reproduced old behavior'} ${route}: ${JSON.stringify(state)}`);
}

async function compareSidebarStyles(page, base) {
  let reference;
  for (const route of ['review', 'schedule', 'focus', 'micro', 'goals', 'team', 'diagnostics', 'profile']) {
    await page.goto(new URL(`#/${route}`, base).href);
    await page.mouse.move(700, 600);
    await page.waitForFunction(route => {
      const frame = document.getElementById('prototype-screen');
      return frame?.title === `时序智配 ${route}` && !frame.classList.contains('route-switching') &&
        frame.contentDocument?.getElementById('ruanchuang-polish-styles')?.sheet &&
        frame.contentDocument?.querySelector('aside nav a[aria-current="page"]');
    }, route);
    const style = await page.locator('#workspace-shell').evaluate(async shell => {
      const doc = shell.ownerDocument;
      await doc.fonts.ready;
      const link = shell.querySelector('a[aria-current="page"]');
      await Promise.all(link.getAnimations({ subtree: true }).map(animation => animation.finished.catch(() => {})));
      const css = getComputedStyle(link);
      const label = getComputedStyle(link.querySelector('span:last-child'));
      const icon = getComputedStyle(link.querySelector('.material-symbols-outlined'));
      return {
        color: label.color, iconColor: icon.color, background: css.backgroundColor,
        fontSize: label.fontSize, fontWeight: label.fontWeight,
        lineHeight: label.lineHeight, borderRadius: css.borderRadius,
        padding: css.padding, shadow: css.boxShadow, height: link.getBoundingClientRect().height,
      };
    });
    console.log(`Sidebar style ${route}: ${JSON.stringify(style)}`);
    reference ||= style;
    assert.deepEqual(style, reference, `${route} selected style differs from review`);
  }
}

try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  // Do not use page.route(): Playwright disables HTTP caching when routing.
  await context.addInitScript(() => { window.__RUANCHUANG_API__ = location.origin + '/api'; });
  const page = await context.newPage();
  await page.goto(`${localUrl}?visit=1#/review`);
  await sidebar(page, 'review', false);
  assert.equal(routerRequests, 1);
  phase = 'updated-unversioned';
  await page.goto(`${localUrl}?visit=2#/review`);
  await sidebar(page, 'review', false);
  assert.equal(routerRequests, 1, 'Old JS should still come from the browser HTTP cache');
  phase = 'release';
  await page.goto(`${localUrl}?visit=3#/review`);
  await sidebar(page, 'review', true);
  assert.equal(await page.locator('html').getAttribute('data-release'), release.release);
  await page.locator('#workspace-shell a[data-route="diagnostics"]').click();
  await sidebar(page, 'diagnostics', true);
  await page.reload();
  await sidebar(page, 'diagnostics', true);
  console.log('Warm HTTP-cache upgrade passed without clearing browser data.');

  // Exercise cleanup on secure origins (localhost/HTTPS). Plain HTTP IP sites
  // cannot register service workers, so their relevant path is HTTP cache above.
  legacyWorker = true;
  await page.evaluate(async (legacyRouter) => {
    localStorage.setItem('release-test-account', 'preserved');
    const cache = await caches.open('flutter-app-cache');
    await cache.put('/stitch/router.js', new Response(legacyRouter, { headers: { 'Content-Type': 'text/javascript' } }));
    const businessCache = await caches.open('user-data');
    await businessCache.put('/draft', new Response('preserved'));
    await navigator.serviceWorker.register('/flutter_service_worker.js');
    await navigator.serviceWorker.ready;
  }, legacyRouter);
  await page.waitForFunction(() => navigator.serviceWorker.controller != null);
  assert.ok(await page.evaluate(async () => (await caches.keys()).includes('flutter-app-cache')));
  legacyWorker = false;
  await page.goto(`${localUrl}?visit=worker-upgrade#/review`);
  await sidebar(page, 'review', true);
  await page.waitForFunction(async () =>
    !(await caches.keys()).includes('flutter-app-cache') &&
    (await navigator.serviceWorker.getRegistrations()).length === 0);
  assert.equal(await page.evaluate(() => localStorage.getItem('release-test-account')), 'preserved');
  assert.ok(await page.evaluate(async () => (await caches.keys()).includes('user-data')));
  console.log('Legacy resource-cache retirement preserves account and business data.');
  await compareSidebarStyles(page, localUrl);
  await context.close();

  if (deployedUrl) {
    const liveContext = await browser.newContext({ viewport: { width: 2048, height: 1120 } });
    const live = await liveContext.newPage();
    const manifest = await (await liveContext.request.get(new URL('release.json', deployedUrl).href)).json();
    assert.equal(manifest.release, release.release, 'The deployed release must match the verified artifact');
    for (const route of ['review', 'diagnostics', 'schedule']) {
      await live.goto(new URL(`#/${route}`, deployedUrl).href);
      await sidebar(live, route, true);
      await live.waitForFunction(() => getComputedStyle(document.getElementById('prototype-screen')).opacity === '1');
      const screenshot = join(root, 'build', `live-${route}.png`);
      await mkdir(dirname(screenshot), { recursive: true });
      await live.screenshot({ path: screenshot });
    }
    await compareSidebarStyles(live, deployedUrl);
    await liveContext.close();
    console.log(`Live release ${manifest.release} verified at ${deployedUrl}`);
  }
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
