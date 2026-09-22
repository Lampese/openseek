import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './desktop_browser_harness.js';

export const prURL = 'https://github.com/owner/project/pull/42';
export const fixture = (name, suffix = 'md') => readFileSync(new URL(`../../fixtures/github-markdown/${name}.${suffix}`, import.meta.url), 'utf8');

export async function openMarkdownPR(page, source, { chat = false, comments = [] } = {}) {
  const app = new DesktopBrowserHarness(page);
  app.markdownSource = source;
  if (chat) app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture HTML' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: source } } },
  ];
  const original = app.replyFor.bind(app);
  const item = { number: 42, title: 'HTML rendering fixture', url: prURL, author: 'contributor', draft: false };
  app.replyFor = request => {
    if (request.method === 'github.list') return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project',
      has_more: false, items: request.params.kind === 'issues' ? [] : [item],
    };
    if (request.method === 'github.pull_request') return {
      item, state: 'OPEN', mergeable: 'MERGEABLE', base: 'main', head: 'feature', body: app.markdownSource,
      additions: 1, deletions: 0, changed_files: 1, checks: [],
      comments: comments.map((body, i) => ({ body, author: 'reviewer', created_at: '2026-09-20T08:00:00Z', url: `${prURL}#issuecomment-${i}` })),
      created_at: '2026-09-20T08:00:00Z', reviewers: [], assignees: [], labels: [],
    };
    return original(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menu', { name: 'New tab', exact: true }).getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  await page.locator('.github-pulls').getByRole('button', { name: /^HTML rendering fixture,/ }).click();
  const body = page.locator('.github-description .markdown');
  await body.waitFor();
  return { app, body };
}

// A comparison projection, not a sanitizer. Strip only documented GitHub
// decoration (including generated @mention links) and our external-navigation
// attributes; retain semantic tags and
// all other attributes so a missing allowlist entry or a leaked event fails.
export function normalizedHTML(html) {
  const template = document.createElement('template');
  template.innerHTML = html;
  function walk(node) {
    if (node.nodeType === 3) return node.data.trim() ? [node.data.replace(/\s+/g, ' ')] : [];
    if (node.nodeType !== 1 && node.nodeType !== 11) return [];
    const children = [...node.childNodes].flatMap(walk).reduce((items, child) => {
      if (typeof child === 'string' && typeof items.at(-1) === 'string') items[items.length - 1] += child;
      else items.push(child);
      return items;
    }, []);
    if (node.nodeType === 11 || ['markdown-accessiblity-table', 'themed-picture'].includes(node.localName) || node.classList.contains('markdown-heading')) return children;
    if (node.localName === 'a' && node.getAttribute('href')?.startsWith('https://camo.githubusercontent.com/') && node.querySelector('img')) return children;
    if (node.localName === 'a' && node.classList.contains('user-mention') && node.getAttribute('data-hovercard-type') === 'user') return children;
    if (node.localName === 'p' && children.length === 1 && children[0][0] === 'img') return children;
    if (node.classList.contains('anchor')) return [];
    const attrs = [...node.attributes].filter(({ name }) =>
      !['class', 'style', 'target', 'rel', 'data-canonical-src'].includes(name) &&
      !(node.localName === 'video' && name === 'preload') &&
      !(node.localName === 'table' && name === 'role') &&
      !(node.localName === 'relative-time' && name === 'title'))
      .map(({ name, value }) => [name, ['href', 'cite', 'longdesc'].includes(name)
        ? new URL(value, 'https://github.com/owner/project/pull/42').href
        : ['src', 'srcset'].includes(name) && node.hasAttribute('data-canonical-src') ? node.getAttribute('data-canonical-src') : value])
      .sort(([a], [b]) => a.localeCompare(b));
    return [[node.localName, attrs, children]];
  }
  return walk(template.content);
}
