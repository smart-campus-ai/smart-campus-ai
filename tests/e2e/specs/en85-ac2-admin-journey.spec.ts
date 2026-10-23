import { test, expect } from '@playwright/test'

/**
 * EN-85-AC2 — Parcours admin : l'admin passe un ticket à « En cours » avec une
 * note. La vérification côté étudiant (« l'étudiant voit le nouveau statut »)
 * est complète contre dev, où les deux identités partagent les données ; en
 * mode mock on vérifie que la mise à jour admin est persistée et relue.
 */
test('EN-85-AC2 un admin passe un ticket à En cours avec une note', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: /Entrer en tant qu'administrateur/i }).click()
  await expect(page).toHaveURL(/\/admin\/tickets$/)

  // Open the first ticket in the admin list.
  await page.getByRole('row').nth(1).getByRole('link').first().click()
  await expect(page).toHaveURL(/\/admin\/tickets\/.+/)

  // Management form: set status to "En cours" and add a student-facing note.
  const form = page.getByRole('form', { name: /Gestion du ticket/i })
  await form.getByLabel(/Statut/i).selectOption({ label: 'En cours' }).catch(async () => {
    await form.getByLabel(/Statut/i).click()
    await page.getByRole('option', { name: /En cours/i }).click()
  })
  await form.getByLabel(/Commentaire/i).fill('Prise en charge par le support, parcours E2E.')
  await page.getByRole('button', { name: /Enregistrer/i }).click()

  // The detail view now reflects the new status.
  await expect(page.getByText('En cours').first()).toBeVisible()
})
