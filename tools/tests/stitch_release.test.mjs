import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { buildStitchWeb } from '../build_stitch_web.mjs';

test('release is deterministic, verifies every file, and versions router and entry together', async () => {
  const root = await mkdtemp(join(tmpdir(), 'stitch-release-test-'));
  const sourceRoot = join(root, 'web');
  const outputRoot = join(root, 'output');
  await mkdir(join(sourceRoot, 'stitch'), { recursive: true });
  await writeFile(join(sourceRoot, 'index.html'), '<script src="stitch/drawer-motion.js" defer></script><script src="stitch/calendar.js" defer></script><script src="stitch/page-host.js" defer></script><script src="stitch/router.js" defer></script>');
  await writeFile(join(sourceRoot, 'stitch/calendar.js'), 'window.StitchCalendar = {};');
  await writeFile(join(sourceRoot, 'stitch/drawer-motion.js'), 'window.createStitchDrawerMotion = () => {};');
  await writeFile(join(sourceRoot, 'stitch/page-host.js'), 'window.createStitchPageHost = () => {};');
  await writeFile(join(sourceRoot, 'stitch/router.js'), 'console.log("version one");');
  const first = await buildStitchWeb({ sourceRoot, outputRoot });
  const second = await buildStitchWeb({ sourceRoot, outputRoot });
  assert.equal(first.release, second.release);
  for (const [file, expected] of Object.entries(first.files)) {
    const actual = createHash('sha256').update(await readFile(join(first.output, file))).digest('hex');
    assert.equal(actual, expected, file);
  }
  const entry = await readFile(join(first.output, 'index.html'), 'utf8');
  assert.ok(entry.includes(`src="${first.router}" data-release="${first.release}"`));
  assert.ok(entry.includes(`src="stitch/page-host.${first.release}.js"`));
  assert.ok(entry.includes(`src="stitch/drawer-motion.${first.release}.js"`));
  assert.ok(entry.includes(`src="stitch/calendar.${first.release}.js"`));
  assert.equal(await readFile(join(first.output, `stitch/calendar.${first.release}.js`), 'utf8'), 'window.StitchCalendar = {};');
  assert.equal(await readFile(join(first.output, `stitch/drawer-motion.${first.release}.js`), 'utf8'), 'window.createStitchDrawerMotion = () => {};');
  assert.equal(await readFile(join(first.output, `stitch/page-host.${first.release}.js`), 'utf8'), 'window.createStitchPageHost = () => {};');

  // Even if a browser caches the old script forever, it cannot substitute it
  // for the new URL. A previous release remains intact for atomic rollback.
  await writeFile(join(sourceRoot, 'stitch/router.js'), 'console.log("version two");');
  const changed = await buildStitchWeb({ sourceRoot, outputRoot });
  assert.notEqual(changed.release, first.release);
  assert.notEqual(changed.router, first.router);
  assert.equal(await readFile(join(first.output, first.router), 'utf8'), 'console.log("version one");');
});

test('rejects a non-Stitch build instead of publishing an unrelated entry', async () => {
  const root = await mkdtemp(join(tmpdir(), 'stitch-release-invalid-'));
  await writeFile(join(root, 'index.html'), '<script src="flutter_bootstrap.js"></script>');
  await assert.rejects(buildStitchWeb({ sourceRoot: root, outputRoot: join(root, 'output') }), /canonical Stitch/);
});
