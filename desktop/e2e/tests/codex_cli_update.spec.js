import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('model menu updates Codex CLI and refreshes the model catalog', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'old-model', displayName: 'Old model' }];
  app.rpcDelays.set('codex.cli.update', 500);
  await app.install();
  await app.goto();
  const trigger = page.getByRole('button', { name: 'Model', exact: true });
  await trigger.click();
  const update = page.getByRole('button', { name: 'Update Codex CLI', exact: true });
  await expect(update).toBeVisible();
  expect(await update.locator('xpath=ancestor::*[@role="listbox"]').count()).toBe(0);
  await update.focus();
  await page.keyboard.press('Enter');
  await expect(update).toBeDisabled();
  await expect(update).toHaveText('Updating…');
  await update.dispatchEvent('click');
  await expect(page.getByText('Updated: codex-cli fixture-new', { exact: true })).toBeVisible();
  await expect(page.getByRole('option', { name: 'GPT-6 Astra', exact: true })).toBeVisible();
  expect(app.requests.filter(r => r.method === 'codex.cli.update')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'codex.model.list').length).toBeGreaterThan(1);
  await update.focus();
  await page.keyboard.press('Escape');
  await expect(trigger).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

test('model menu keeps update errors visible and allows retry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('codex.cli.update', 'Update failed: permission denied');
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  const update = page.getByRole('button', { name: 'Update Codex CLI', exact: true });
  await update.click();
  await expect(page.locator('.custom-select-action-detail')).toContainText('permission denied');
  await expect(update).toBeEnabled();
  app.rpcErrors.delete('codex.cli.update');
  await update.click();
  await expect(page.getByText('Updated: codex-cli fixture-new', { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});


test('background Codex activity disables CLI update', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  app.notify('codex.notification', {
    method: 'turn/started',
    params: { threadId: 'background-thread', turn: { id: 'background-turn', status: 'inProgress', items: [] } },
    generation: 1,
  });
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  const update = page.getByRole('button', { name: 'Update Codex CLI', exact: true });
  await expect(update).toBeDisabled();
  await expect(page.locator('.custom-select-action-detail')).toHaveText('Finish running Codex tasks before updating');
  await update.dispatchEvent('click');
  expect(app.requests.filter(r => r.method === 'codex.cli.update')).toHaveLength(0);
});
