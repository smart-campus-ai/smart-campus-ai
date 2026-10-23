import { test, expect } from '@playwright/test'

/**
 * EN-85-AC1 — Parcours étudiant : connexion, création d'un ticket, puis
 * consultation dans « Mes tickets » au statut « Ouvert ».
 *
 * Runs against the mock-served SPA (VITE_USE_MOCKS=true) locally and the
 * deployed dev stack in CI. In mock mode the login screen offers a demo
 * role chooser; against dev the auth step is handled by the test identities
 * wired through the Cognito Hosted UI (see the e2e README).
 */
test('EN-85-AC1 un étudiant crée un ticket et le retrouve au statut Ouvert', async ({ page }) => {
  await page.goto('/login')

  // Sign in as a student (mock demo mode).
  await page.getByRole('button', { name: /Entrer en tant qu'étudiant/i }).click()

  // Lands on "Mes tickets".
  await expect(page).toHaveURL(/\/tickets$/)

  // Open the new-ticket dialog and fill the form.
  const unique = `Wi-Fi HS E2E ${Date.now()}`
  await page.getByRole('button', { name: /Nouveau ticket/i }).first().click()

  const form = page.getByRole('form', { name: /Création d'un ticket/i })
  await form.getByLabel(/Titre/i).fill(unique)
  await form.getByLabel(/Description/i).fill('Plus de Wi-Fi depuis ce matin, parcours E2E.')
  // Category is required; select the first real option (incident).
  await form.getByLabel(/Catégorie/i).selectOption({ label: 'incident' }).catch(async () => {
    // Fallback for a custom select widget.
    await form.getByLabel(/Catégorie/i).click()
    await page.getByRole('option', { name: /incident/i }).click()
  })

  await page.getByRole('button', { name: /^Créer le ticket$|^Créer$/i }).click()

  // After creation the app opens the new ticket: its detail shows the title and
  // the "Ouvert" status (US04-AC: a new ticket starts at "Ouvert").
  await expect(page.getByRole('heading', { name: unique, level: 1 })).toBeVisible()
  await expect(page.getByText('Ouvert').first()).toBeVisible()

  // And it is listed under "Mes tickets" at status "Ouvert".
  await page.getByRole('link', { name: /Mes tickets/i }).first().click()
  await expect(page).toHaveURL(/\/tickets$/)
  const row = page.getByRole('row', { name: new RegExp(unique) })
  await expect(row).toBeVisible()
  await expect(row.getByText('Ouvert')).toBeVisible()
})
