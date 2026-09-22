import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const market = {
  name: 'wayfinder', module_name: 'Yoorkin/wayfinder', package_path: '',
  version: '0.1.0', description: 'Plan uncertain work.', author: 'Yoorkin', repository: '',
};
const installed = {
  id: 'yoorkin-wayfinder', name: 'wayfinder', description: market.description,
  source: 'Yoorkin/wayfinder@0.1.0',
};

class SkillsHarness extends DesktopBrowserHarness {
  constructor(page, alreadyInstalled = false) {
    super(page);
    this.installedSkills = alreadyInstalled ? [structuredClone(installed)] : [];
    this.catalogSkills = [structuredClone(market)];
  }

  replyFor(request) {
    switch (request.method) {
      case 'skills.catalog': return { skills: this.catalogSkills };
      case 'skills.content':
      case 'skills.installed_content':
        return { kind: 'content', content: '# Wayfinder\n\nPlan uncertain work.', absolute: '', sig: '' };
      case 'skills.install':
        this.installedSkills = [structuredClone(installed)];
        return { installed };
      case 'skills.uninstall':
        if (request.params.id !== installed.id) throw new Error('Wrong library id');
        this.installedSkills = [];
        return { removed: true };
      default: return super.replyFor(request);
    }
  }

  async openDetails(fromCatalog = false) {
    await this.install();
    await this.goto();
    await this.page.getByRole('button', { name: 'Skills', exact: true }).click();
    const summaries = this.page.locator('.skill-summary');
    await (fromCatalog ? summaries.last() : summaries.first()).click();
    await expect(this.page.locator('.skill-preview-markdown')).toContainText('Plan uncertain work.');
  }
}

test('install and uninstall from the same catalog detail page', async ({ page }) => {
  const app = new SkillsHarness(page);
  await app.openDetails();
  await page.getByRole('button', { name: 'Install skill', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  expect(app.requests.filter(r => r.method === 'skills.uninstall').map(r => r.params.id)).toEqual([installed.id]);
  expect(app.installedSkills).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('removed skill without a catalog entry cannot be uninstalled again', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.catalogSkills = [];
  await app.openDetails();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.locator('.skill-detail-header')).toContainText('Not installed');
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toHaveCount(0);
  expect(app.installedSkills).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

for (const source of ['Yoorkin/wayfinder@0.0.9', 'Yoorkin/wayfinder@0.1.0/other']) {
  test(`catalog detail keeps install available for a different source: ${source}`, async ({ page }) => {
    const app = new SkillsHarness(page, true);
    app.installedSkills[0].source = source;
    await app.openDetails(true);
    await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });
}

test('installed detail stops offering uninstall after the library removes it', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  await app.openDetails();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect.poll(() => app.installedSkills.length).toBe(0);
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Install skill', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('uninstall failure is visible in the detail page and can be retried', async ({ page }) => {
  const app = new SkillsHarness(page, true);
  app.rpcErrors.set('skills.uninstall', 'Cannot remove skill: permission denied');
  await app.openDetails();
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.locator('.skill-detail-page')).toContainText('Cannot remove skill: permission denied');
  await expect(page.getByRole('button', { name: 'Uninstall', exact: true })).toBeEnabled();
  app.rpcErrors.delete('skills.uninstall');
  await page.getByRole('button', { name: 'Uninstall', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Install skill', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});
