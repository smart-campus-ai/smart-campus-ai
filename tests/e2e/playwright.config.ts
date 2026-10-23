import { defineConfig, devices } from '@playwright/test'

/**
 * EN-85 — Playwright configuration.
 *
 * Two modes:
 * - Local / CI without AWS (default): the SPA runs mock-first
 *   (VITE_USE_MOCKS=true, src/api/mock.ts). Playwright builds and previews the
 *   frontend, so the critical journeys are exercised end-to-end in a real
 *   browser without any deployed backend. Deterministic and offline.
 * - Against deployed dev: set E2E_BASE_URL to the CloudFront URL. The webServer
 *   is then skipped and the tests run against the real stack (EN-74), which is
 *   how they run in CI after the dev deploy.
 */
const externalBaseUrl = process.env.E2E_BASE_URL
const previewPort = 4173
const baseURL = externalBaseUrl ?? `http://localhost:${previewPort}`

export default defineConfig({
  testDir: './specs',
  // AC: journeys are sequential per story; keep runs reproducible.
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [
    ['list'],
    // DoD: report and traces kept as an artifact.
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  // Only spin up the local mock-served SPA when no external URL is provided.
  webServer: externalBaseUrl
    ? undefined
    : {
        // Build once, then preview the static SPA with mocks enabled.
        command: 'pnpm --dir ../../frontend run build && pnpm --dir ../../frontend exec vite preview --port 4173 --strictPort',
        url: `http://localhost:${previewPort}`,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        env: { VITE_USE_MOCKS: 'true' },
      },
})
