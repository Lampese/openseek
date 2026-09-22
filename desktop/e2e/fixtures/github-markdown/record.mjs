// Explicit maintenance command. The browser tests never invoke the API.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { chromium } from '@playwright/test';
import { normalizedHTML } from '../../tests/support/github_markdown.js';

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  for (const name of ['tags', 'attributes', 'mixed', 'media', 'review-summary']) {
    const path = suffix => new URL(`./${name}.${suffix}`, import.meta.url);
    if (process.argv.includes('--fetch')) {
      const response = execFileSync('gh', ['api', 'markdown', '--method', 'POST', '--input', '-'], {
        input: JSON.stringify({ mode: 'gfm', text: readFileSync(path('md'), 'utf8') }), encoding: 'utf8',
      });
      writeFileSync(path('github.html'), response);
    }
    const normalized = await page.evaluate(normalizedHTML, readFileSync(path('github.html'), 'utf8'));
    writeFileSync(path('normalized.json'), JSON.stringify(normalized, null, 2) + '\n');
  }
} finally {
  await browser.close();
}
