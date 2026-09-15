import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('PTC results retain nested edit diffs and interrupted calls across reload', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture: update the note with a program' } } },
    { sequence: 2, item: { kind: 'assistant', payload: {
      content: '', tool_calls: [{ id: 'program', name: 'mbtx', arguments: JSON.stringify({
        ptc: true, source: 'async fn main { /* call host tools */ }', description: 'Update note',
      }) }],
    } } },
    { sequence: 3, item: { kind: 'tool_result', payload: {
      tool_call_id: 'program', tool_name: 'mbtx', content: 'Program interrupted', is_error: true,
      data: { ptc_calls: [
        { name: 'edit', arguments: { path: 'note.txt', start_line: 1, old_string: 'before', new_string: 'after' },
          status: 'done', result: { content: 'Updated note.txt', is_error: false } },
        { name: 'web_search', arguments: { query: 'MoonBit documentation' }, status: 'interrupted' },
      ] },
    } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  for (let pass = 0; pass < 2; pass++) {
    const outer = page.locator('#transcript details.tool-call').first();
    await outer.locator(':scope > summary').click();
    await expect(outer.getByText('Program tool calls (2)', { exact: true })).toBeVisible();
    const edit = outer.locator('details.tool-call').first();
    await edit.locator(':scope > summary').click();
    await expect(edit).toContainText('before');
    await expect(edit).toContainText('after');
    await expect(edit.locator(':scope > summary').getByRole('img', { name: 'Tool succeeded' })).toBeVisible();
    const search = outer.locator('details.tool-call').nth(1);
    await expect(search.locator(':scope > summary').getByRole('img', { name: 'Tool failed' })).toBeVisible();
    const interrupted = outer.locator('details.tool-result').last();
    await interrupted.locator(':scope > summary').click();
    await expect(interrupted).toContainText('Program call interrupted; changes may have occurred.');
    if (pass === 0) {
      await page.screenshot({ path: testInfo.outputPath('program-calls.png') });
      await page.reload();
      await app.openSession();
    }
  }
  expect(app.pageErrors).toEqual([]);
});
