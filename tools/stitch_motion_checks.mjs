import assert from 'node:assert/strict';

export async function checkPageMotion(page, go) {
  await page.evaluate(async () => {
    await Promise.all(document.getAnimations().map(a => a.finished.catch(() => {})));
    const animate = Element.prototype.animate;
    window.restorePageAnimation = () => { Element.prototype.animate = animate; };
    Element.prototype.animate = function (...args) {
      const animation = animate.apply(this, args);
      // Inspect real rendered transitions at 10% speed, then hold exact frames.
      if (this.matches('.workspace-page')) animation.playbackRate = 0.1;
      return animation;
    };
  });
  await go('schedule');
  const middle = await page.evaluate(() => {
    const frame = document.getElementById('prototype-screen');
    for (const a of frame.getAnimations()) { a.pause(); a.currentTime = 90; }
    const old = [...document.querySelectorAll('.workspace-page')].find(f => f.title === '时序智配 micro');
    return { opacity: Number(getComputedStyle(frame).opacity), transform: getComputedStyle(frame).transform,
      outgoing: getComputedStyle(old).visibility, inert: old.inert, ariaHidden: old.getAttribute('aria-hidden') };
  });
  assert.ok(middle.opacity > 0 && middle.opacity < 1, 'Content must blend, not appear fully opaque in the first frame');
  assert.equal(middle.transform, 'none', 'Dense content must stay spatially stable');
  assert.equal(middle.outgoing, 'visible', 'Keep old pixels underneath until the new page covers them');
  assert.equal(middle.inert, true); assert.equal(middle.ariaHidden, 'true');
  await page.screenshot({ path: 'build/navigation-motion-midpoint.png' });
  await go('micro');
  const reverse = await page.evaluate(() => {
    const old = [...document.querySelectorAll('.workspace-page')].find(f => f.title === '时序智配 schedule');
    for (const a of old.getAnimations()) { a.pause(); a.currentTime = 0; }
    return Number(getComputedStyle(old).opacity);
  });
  assert.ok(Math.abs(reverse - middle.opacity) < 0.03, 'Reversing must start from the current opacity without a jump');
  await page.evaluate(() => {
    for (const a of document.getAnimations()) if (a.effect.target.matches('.workspace-page')) a.finish();
    window.restorePageAnimation();
  });
  await page.waitForFunction(() => !document.querySelector('[data-transition-layer]'));
  assert.equal(await page.locator('.workspace-page').evaluateAll(frames => frames.filter(f => getComputedStyle(f).visibility === 'visible').length), 1);
  console.log('Slow-motion midpoint, continuous reversal and outgoing-layer cleanup passed.');
}
