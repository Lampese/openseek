import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { fixture, normalizedHTML, openMarkdownPR, prURL } from './support/github_markdown.js';

for (const name of ['tags', 'attributes', 'mixed', 'media', 'review-summary']) {
  test(`PR HTML matches the offline GitHub ${name} fixture`, async ({ page }) => {
    if (name === 'media') await page.route('https://**/*', route => route.fulfill({
      contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>',
    }));
    const { app, body } = await openMarkdownPR(page, fixture(name));
    await expect(body.locator('.markdown-fallback, .raw-html')).toHaveCount(0);
    const actual = await page.evaluate(normalizedHTML, await body.innerHTML());
    const expected = JSON.parse(fixture(name, 'normalized.json'));
    expect(actual).toEqual(expected);
    expect(app.pageErrors).toEqual([]);
  });
}

test('the reported Codex review summary renders its complete disclosure and fractional timestamp', async ({ page }, testInfo) => {
  await page.clock.install({ time: new Date('2026-09-20T03:51:43Z') });
  const source = fixture('review-summary');
  const { app, body } = await openMarkdownPR(page, source, { chat: true });
  await expect(body).not.toContainText('codex-pull-request-review-summary');
  await expect(body.getByRole('heading', { name: 'Codex Review Summary' })).toBeVisible();
  await expect(body.locator('table th')).toHaveText(['Review', 'Status', 'Commit', 'Review trigger']);
  await expect(body.locator('table code')).toHaveText('fdab425');
  await expect.poll(() => body.locator('relative-time').evaluate(el => el.shadowRoot?.textContent)).toBe('2 minutes ago');
  const details = body.locator('details');
  await expect(details.getByRole('list')).toBeHidden();
  await details.locator('summary').click();
  await expect(details.locator('li')).toHaveCount(3);
  await expect(details.getByText('Codex reacts with', { exact: false })).toBeVisible();
  await body.screenshot({ path: testInfo.outputPath('codex-review-summary.png') });
  const chat = page.locator('#transcript');
  await expect(chat.locator('details, relative-time')).toHaveCount(0);
  await expect(chat).toContainText('<!-- codex-pull-request-review-summary -->');
  await expect(chat).toContainText('<relative-time datetime="2026-09-20T03:49:43.007844Z">');
  await expect(chat).toContainText('<details> <summary>');
  await chat.screenshot({ path: testInfo.outputPath('codex-review-summary-chat.png') });
  expect(app.pageErrors).toEqual([]);
});

test('complete PR comments retain disclosures and updating relative times while chat keeps HTML source', async ({ page }, testInfo) => {
  await page.clock.install({ time: new Date('2026-09-20T08:00:30Z') });
  const source = fixture('mixed');
  const { app, body } = await openMarkdownPR(page, source, { chat: true, comments: [source] });
  const outer = body.locator('details').first();
  await expect(body).not.toContainText('seekmoon-hidden-comment');
  await expect(body.locator('table')).toHaveCount(1);
  await expect(outer.getByText('First Markdown paragraph', { exact: false })).not.toBeVisible();
  await expect(body.getByText('Outside both disclosures:', { exact: false })).toBeVisible();
  await outer.locator(':scope > summary').click();
  await expect(outer.getByText('Final paragraph still inside', { exact: false })).toBeVisible();
  await expect(outer.locator('details')).toHaveAttribute('open', '');
  const time = body.locator('relative-time');
  await expect.poll(() => time.evaluate(el => el.shadowRoot?.textContent)).toBe('now');
  const handle = await outer.elementHandle();
  await page.locator('#task').fill('Unrelated render');
  await expect.poll(() => handle.evaluate(el => el.isConnected && el.open)).toBe(true);
  await page.clock.fastForward(90_000);
  await expect.poll(() => time.evaluate(el => el.shadowRoot?.textContent)).toContain('2 minutes ago');
  const comment = page.locator('.github-comment:not(.github-description) .markdown');
  await expect(comment.locator('details')).toHaveCount(2);
  await expect.poll(() => comment.locator('relative-time').evaluate(el => el.shadowRoot?.textContent)).toContain('2 minutes ago');
  const chat = page.locator('#transcript');
  await expect(chat.locator('relative-time, details')).toHaveCount(0);
  await expect(chat).toContainText('<relative-time datetime=');
  await expect(chat).toContainText('<!-- seekmoon-hidden-comment -->');
  await body.screenshot({ path: testInfo.outputPath('complete-comment.png') });
  app.markdownSource = source.replaceAll('2026-09-20T08:00:00Z', '2026-09-20T07:00:00Z');
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  await expect(time).toHaveAttribute('datetime', '2026-09-20T07:00:00Z');
  await expect.poll(() => time.evaluate(el => el.shadowRoot?.textContent)).toContain('hour ago');
  await expect.poll(() => handle.evaluate(el => el.isConnected && el.open)).toBe(true);
  await outer.locator(':scope > summary').click();
  await expect(outer.getByText('Final paragraph still inside', { exact: false })).not.toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('PR code retains copying, highlighting and diagram interactions across refreshes', async ({ page }, testInfo) => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const code = 'fn main {\n  println("<details>literal</details>")\n}';
  const source = [
    '<details open><summary>Code and diagrams</summary>',
    `\`\`\`moonbit\n${code}\n\`\`\``,
    '```mermaid\nflowchart LR\nAlpha --> Beta\n```',
    '```d2\none -> two\n```',
    '```uml\n@startuml\nparticipant Alice\nAlice -> Bob : hello\n@enduml\n```',
    '```mermaid\nunfinished --> fence',
  ].join('\n\n');
  const { app, body } = await openMarkdownPR(page, source);
  await expect(body.locator('.chat-code-block')).toHaveCount(5);
  await expect(body.locator('.moonbit-source [class^="mtk"]').first()).toBeVisible();
  const block = body.locator('.chat-code-block').first();
  await block.hover();
  await block.getByRole('button', { name: 'Copy code', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(code);
  await expect(block.getByRole('button', { name: 'Copied', exact: true })).toBeVisible();
  const mermaid = body.locator('.chat-mermaid svg');
  await expect(mermaid).toContainText('Alpha');
  await expect(body.locator('[data-diagram-language="diago"] svg:not(svg svg)')).toHaveCount(1);
  await expect(body.locator('[data-diagram-language="uml"] svg')).toHaveCount(1);
  await expect(body.locator('.moonbit-viewer-markdown-diagram-viewport')).toHaveCount(3);
  await expect(body.locator('pre code.language-mermaid')).toHaveText('unfinished --> fence');
  const handle = await mermaid.elementHandle();
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'github.pull_request').length).toBe(2);
  await expect.poll(() => handle.evaluate(el => el.isConnected)).toBe(true);
  await expect(body.locator('.moonbit-viewer-markdown-diagram-viewport')).toHaveCount(3);
  await body.screenshot({ path: testInfo.outputPath('code-and-diagrams.png') });
  expect(app.pageErrors).toEqual([]);
});

test('HTML parser failure falls back to source and the next refresh recovers', async ({ page }) => {
  const { app, body } = await openMarkdownPR(page, '<b>initial</b>');
  await page.evaluate(() => {
    window.savedCreateElement = document.createElement;
    document.createElement = function(tag, ...args) {
      if (tag === 'template') throw new Error('injected inert parser failure');
      return window.savedCreateElement.call(this, tag, ...args);
    };
  });
  app.markdownSource = '<details><summary>New input</summary>content</details>';
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  await expect(body.locator('.markdown-fallback')).toHaveText(app.markdownSource);
  await page.evaluate(() => { document.createElement = window.savedCreateElement; delete window.savedCreateElement; });
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  await expect(body.locator('details summary')).toHaveText('New input');
  await expect(body.locator('.markdown-fallback')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('HTML filtering is inert and cannot forge code blocks or app actions', async ({ page }) => {
  const requests = [];
  await page.route('https://attacker.example/**', route => { requests.push(route.request().url()); return route.abort(); });
  const source = [
    '<!-- secret -->',
    '<script>window.markdownExecuted=true</script>',
    '<iframe src="https://attacker.example/frame">frame text</iframe>',
    '<object data="https://attacker.example/object"><b>kept content</b></object>',
    '<img src="javascript:alert(1)" onerror="window.markdownExecuted=true">',
    '<a href="java&#x09;script:alert(1)" onclick="bad()">unsafe HTML link</a>',
    '[unsafe Markdown](javascript:alert(1)) <javascript:alert(1)>',
    '<div id="app" name="task" class="chat-mermaid" style="position:fixed" data-transcript-diagram="mermaid" data-transcript-image="/tmp/private">safe div</div>',
    '<template><strong>template content</strong></template>',
    '<!-- seekmoon-code-0:0 --><seekmoon-code-0>0</seekmoon-code-0>',
    '```html\n<details><script>literal</script></details>\n```',
    '`<img src="https://attacker.example/code">`',
  ].join('\n\n');
  const { app, body } = await openMarkdownPR(page, source);
  await expect(body.locator('script, iframe, object, template, [onclick], [onerror], [style], #app, .chat-mermaid, .transcript-image')).toHaveCount(0);
  await expect(body.locator('#user-content-app')).toHaveAttribute('name', 'user-content-task');
  for (const label of ['unsafe HTML link', 'unsafe Markdown', 'javascript:alert(1)']) {
    await expect(body.getByRole('link', { name: label, exact: true })).toHaveCount(0);
  }
  await expect(body.locator('.chat-code-block')).toHaveCount(1);
  await expect(body.locator('.chat-code-block code')).toHaveText('<details><script>literal</script></details>');
  await expect(body).toContainText('<script>window.markdownExecuted=true</script>');
  await expect(body.locator('b')).toHaveText('kept content');
  await expect(body.locator('strong')).toHaveText('template content');
  expect(requests).toEqual([]);
  expect(await page.evaluate(() => window.markdownExecuted)).toBeUndefined();
  expect(app.pageErrors).toEqual([]);
});

test('HTML media resolve against the PR, picture selects its source and video has controls', async ({ page }, testInfo) => {
  const requests = [];
  const clip = readFileSync(new URL('../fixtures/github-markdown/clip.webm', import.meta.url));
  await page.route('https://**/*', route => {
    requests.push(route.request().url());
    if (route.request().url().endsWith('/clip.webm')) return route.fulfill({ contentType: 'video/webm', body: clip });
    return route.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="#729ac4"/></svg>' });
  });
  const { app, body } = await openMarkdownPR(page, [
    '![Markdown image](media/markdown.svg)',
    '<img alt="HTML image" src="../media/html.svg" width="2400" height="1200">',
    '<picture><source srcset="media/picture.svg 1x, media/picture-2.svg 2x" media="(min-width: 1px)" type="image/svg+xml"><img alt="Picture fallback" src="media/fallback.svg"></picture>',
    '<video src="media/clip.webm" width="2400" height="1200" autoplay onplay="bad()">Video fallback</video>',
    '<img alt="blocked" src="file:///tmp/private.png"><source srcset="javascript:alert(1)">',
    '[Ordinary link](../blob/main/README.md) <a href="../blob/main/README.md">HTML link</a>',
  ].join('\n\n'));
  await expect(body.getByRole('img', { name: 'Markdown image' })).toHaveAttribute('src', prURL.replace('/42', '/media/markdown.svg'));
  await expect(body.getByRole('img', { name: 'HTML image' })).toHaveAttribute('src', 'https://github.com/owner/project/media/html.svg');
  await expect.poll(() => body.locator('picture img').evaluate(el => el.currentSrc)).toBe('https://github.com/owner/project/pull/media/picture.svg');
  await expect.poll(() => body.locator('img[src]').evaluateAll(images => images.every(el => el.naturalWidth === 80))).toBe(true);
  const video = body.locator('video');
  await expect(video).toHaveAttribute('controls', '');
  await expect(video).not.toHaveAttribute('autoplay');
  await expect(video).toHaveAttribute('src', 'https://github.com/owner/project/pull/media/clip.webm');
  await expect.poll(() => video.evaluate(el => el.readyState)).toBeGreaterThanOrEqual(2);
  expect(await video.evaluate(el => el.paused)).toBe(true);
  await video.press('Space');
  await expect.poll(() => video.evaluate(el => el.currentTime)).toBeGreaterThan(0);
  await video.press('Space');
  await expect.poll(() => video.evaluate(el => el.paused)).toBe(true);
  await expect(body.getByRole('img', { name: 'blocked' })).not.toHaveAttribute('src');
  for (const label of ['Ordinary link', 'HTML link']) await expect(body.getByRole('link', { name: label, exact: true })).toHaveAttribute('href', 'https://github.com/owner/project/blob/main/README.md');
  for (const width of [1440, 900]) {
    await page.setViewportSize({ width, height: 900 });
    expect(await body.evaluate(root => [...root.querySelectorAll('img, video, picture')].every(el => el.getBoundingClientRect().width <= root.clientWidth + 1))).toBe(true);
  }
  expect(requests.some(url => url.endsWith('/media/markdown.svg'))).toBe(true);
  await body.screenshot({ path: testInfo.outputPath('inline-media.png') });
  expect(app.pageErrors).toEqual([]);
});
