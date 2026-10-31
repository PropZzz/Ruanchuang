import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../../', import.meta.url);

async function source(path) {
  return readFile(new URL(path, root), 'utf8');
}

test('mobile Stitch shell owns the shared bottom navigation and constrains profile content', async () => {
  const [host, entry, polish, profile] = await Promise.all([
    source('web/stitch/page-host.js'),
    source('web/index.html'),
    source('web/stitch/mobile/assets/polish.css'),
    source('web/stitch/screens/profile/index.html'),
  ]);

  assert.match(host, /class="shell-mobile-nav"/, 'page host must render one shared mobile navigation');
  assert.match(host, /desktopShell:\s*primary\.has\(route\)/, 'primary routes must keep the persistent shell on mobile');
  assert.match(entry, /#workspace-shell \.shell-mobile-nav\s*\{/, 'outer shell must style the mobile navigation');
  assert.match(polish, /html\[data-route='profile'\] body > aside\.fixed\s*\{[^}]*display:\s*none\s*!important/s, 'profile must not render a second mobile navigation');
  assert.match(polish, /html\[data-route='profile'\] main[\s\S]*overflow-x:\s*hidden/, 'profile content must clip horizontal overflow on mobile');
  assert.match(polish, /html\[data-route='profile'\] main[\s\S]*\.rounded-xl[\s\S]*min-width:\s*0/, 'profile cards must be allowed to shrink in a narrow viewport');
  assert.match(polish, /html\[data-route='profile'\] main \[data-profile-metrics\][\s\S]*flex-wrap:\s*wrap/, 'profile metric values must wrap on narrow screens');
  assert.match(profile, /data-profile-metrics/, 'profile metric strip must expose a stable responsive hook');
});
