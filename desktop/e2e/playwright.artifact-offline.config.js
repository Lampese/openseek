import { defineConfig } from '@playwright/test';

// Requests for assets are fulfilled by DesktopBrowserHarness. There is no
// webServer entry, so this suite never starts an app, backend or HTTP server.
export default defineConfig({
  testDir: './tests',
  testMatch: ['transcript_artifact_files.spec.js'],
  timeout: 45_000,
  workers: 1,
  reporter: 'list',
  use: { baseURL: 'http://127.0.0.1:5175', headless: true },
});
