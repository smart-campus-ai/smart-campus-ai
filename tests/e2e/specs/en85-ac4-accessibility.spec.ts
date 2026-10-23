import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

/**
 * EN-85-AC4 — Accessibilité automatisée : un scan axe-core sur les pages des
 * parcours ne remonte aucune violation de niveau critique. L'automatisé ne
 * remplace pas une revue manuelle avec technologies d'assistance (NFR).
 */

async function loginStudent(page: import('@playwright/test').Page) {
  await page.goto('/login')
  await page.getByRole('button', { name: /Entrer en tant qu'étudiant/i }).click()
  await expect(page).toHaveURL(/\/tickets$/)
}

async function scan(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa'])
    .analyze()
  const critical = results.violations.filter((v) => v.impact === 'critical')
  return { results, critical }
}

test('EN-85-AC4 la page de connexion n’a aucune violation critique', async ({ page }) => {
  await page.goto('/login')
  const { critical } = await scan(page)
  expect(critical, JSON.stringify(critical.map((v) => v.id))).toHaveLength(0)
})

test('EN-85-AC4 « Mes tickets » n’a aucune violation critique', async ({ page }) => {
  await loginStudent(page)
  const { critical } = await scan(page)
  expect(critical, JSON.stringify(critical.map((v) => v.id))).toHaveLength(0)
})

test('EN-85-AC4 l’assistant de chat n’a aucune violation critique', async ({ page }) => {
  await loginStudent(page)
  await page.getByRole('link', { name: /Assistant|Chat/i }).first().click()
  await expect(page).toHaveURL(/\/chat$/)
  const { critical } = await scan(page)
  expect(critical, JSON.stringify(critical.map((v) => v.id))).toHaveLength(0)
})
