import { test, expect } from '@playwright/test'

/**
 * EN-85-AC3 — Parcours chat vers ticket : l'étudiant pose une question hors
 * base de connaissances, l'assistant répond « je ne sais pas » et propose de
 * créer un ticket ; le formulaire s'ouvre pré-rempli (US10-AC2).
 */
test('EN-85-AC3 une question hors KB propose un ticket pré-rempli', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: /Entrer en tant qu'étudiant/i }).click()
  await expect(page).toHaveURL(/\/tickets$/)

  // Go to the chat.
  await page.getByRole('link', { name: /Assistant|Chat/i }).first().click()
  await expect(page).toHaveURL(/\/chat$/)

  // Ask something the knowledge base cannot answer.
  const question = 'Quelle est la météo sur Mars demain ?'
  const input = page.getByPlaceholder(/Écrivez votre message/i)
  await input.fill(question)
  await page.getByRole('button', { name: /^Envoyer$/i }).click()

  // The assistant surfaces a "Créer un ticket" action on the unanswered reply.
  const escalate = page.getByRole('button', { name: /Créer un ticket/i }).first()
  await expect(escalate).toBeVisible()
  await escalate.click()

  // The ticket form opens prefilled from the conversation (US10-AC2).
  const form = page.getByRole('form', { name: /Création d'un ticket/i })
  await expect(form).toBeVisible()
  const title = form.getByLabel(/Titre/i)
  const description = form.getByLabel(/Description/i)
  // Prefill derives from the student's own message: non-empty, carrying the question.
  await expect(title).not.toHaveValue('')
  await expect(description).toHaveValue(/Mars|météo/i)
})
