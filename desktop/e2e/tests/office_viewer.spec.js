import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('file tabs render real DOCX and XLSX packages through the Office surface', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [
    { name: 'report.docx', is_dir: false },
    { name: 'book1.xlsx', is_dir: false },
  ];
  app.searchFiles = ['docs/report.docx', 'docs/book1.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();

  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();

  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('report.docx');
  await page.getByRole('option', { name: /report\.docx/ }).click();
  await expect(page.locator('.office-viewer-surface.word-surface')).toBeVisible();
  await expect(page.locator('.word-page')).toContainText('Walking on imported air');
  await expect(page.locator('.viewer-notice')).toHaveClass(/hidden/);
  await expect(page.locator('.office-viewer-toolbar')).toBeVisible();
  await expect(page.locator('.office-viewer-zoom-value')).toHaveText('100%');
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect(page.locator('.office-viewer-zoom-value')).toHaveText('110%');
  await expect(page.locator('#openseek-office-surface')).toHaveCSS('--office-zoom', '1.1');
  await expect(page.locator('.word-page').first()).toHaveCSS('zoom', '1.1');
  await page.getByRole('searchbox', { name: 'Find in document', exact: true }).fill('Walking');
  await expect(page.locator('.word-page svg text.office-search-hit')).toHaveCount(1);
  await page.getByRole('button', { name: 'Office font source', exact: true }).click();
  await expect(page.locator('#openseek-office-surface')).toHaveClass(/prefer-system-fonts/);

  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('book1.xlsx');
  await page.getByRole('option', { name: /book1\.xlsx/ }).click();
  await expect(page.locator('.office-viewer-surface.sheet-surface')).toBeVisible();
  await expect(page.locator('.sheet-document table').first()).toBeVisible();
  // E11 is an uncached formula in the fixture (B2+B3). The Office surface
  // must show the calculated result instead of exposing formula-pending text.
  await expect(page.locator('td[data-cell="E11"]')).toHaveText('43');
  await expect(page.locator('td.formula-pending')).toHaveCount(0);
  await expect(page.locator('.word-page')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Word selection becomes an Office composer mention and reaches agent.start', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'report.docx', is_dir: false }];
  app.searchFiles = ['docs/report.docx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('report.docx');
  await page.getByRole('option', { name: /report\.docx/ }).click();
  await expect(page.locator('.word-page svg text').first()).toBeVisible();

  // Exercise the browser's native SVG Range path used by office-viewer. The
  // viewer's document-level selectionchange listener then emits its JSON
  // envelope through the real Rabbita command bridge.
  await page.locator('.word-page svg text').first().evaluate(element => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  await expect(page.locator('.mention-chip')).toContainText('Office selection');

  await page.locator('#task').fill('Explain the selected Office text');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain('<office_selection>');
  const task = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(task).toContain('office.selection.materialized.v1');
  expect(task).toContain('Walking on imported air');
  expect(task).toContain('/workspace/docs/report.docx');
  expect(task).toContain('Explain the selected Office text');
  expect(app.pageErrors).toEqual([]);
});

test('Excel range selection replaces the prior Office chip with structured cell context', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'book1.xlsx', is_dir: false }];
  app.searchFiles = ['docs/book1.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('book1.xlsx');
  await page.getByRole('option', { name: /book1\.xlsx/ }).click();
  const cells = page.locator('.sheet-document td[data-cell]');
  await expect(cells.first()).toBeVisible();
  const first = await cells.first().boundingBox();
  const second = await cells.nth(Math.min(1, await cells.count() - 1)).boundingBox();
  await page.mouse.move(first.x + first.width / 2, first.y + first.height / 2);
  await page.mouse.down();
  await page.mouse.move(second.x + second.width / 2, second.y + second.height / 2);
  await page.mouse.up();
  await expect(page.locator('.mention-chip')).toContainText('Office selection');

  await page.locator('#task').fill('Inspect the selected cells');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain('<office_selection>');
  const task = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(task).toContain('office.selection.materialized.v1');
  expect(task).toContain('/workspace/docs/book1.xlsx');
  expect(task).toContain('"kind": "excel"');
  expect(task).toContain('"range": "A1:B1"');
  expect(task).toContain('Inspect the selected cells');
  expect(app.pageErrors).toEqual([]);
});
