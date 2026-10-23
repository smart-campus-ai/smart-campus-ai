import { describe, expect, it } from 'vitest'
import { Route, Routes, useLocation } from 'react-router-dom'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ChatPage } from '@/pages/student/ChatPage'
import { MockApi } from '@/api/mock'
import { renderWithProviders } from '@/test/render'

/** Probe that exposes the router state pushed to /tickets/new. */
function NewTicketProbe() {
  const location = useLocation()
  const state = location.state as { prefill?: { title?: string; description?: string } } | null
  return <div data-testid="prefill">{JSON.stringify(state?.prefill ?? {})}</div>
}

describe('US10 — escalade du chat vers un ticket (UI)', () => {
  it('US10-AC2 pré-remplit le formulaire avec le contexte de la conversation', async () => {
    const api = new MockApi({ sub: 'student-001', email: 'alice@esiea.fr', role: 'student' })
    const user = userEvent.setup()

    renderWithProviders(
      <Routes>
        <Route path="/chat" element={<ChatPage />} />
        <Route path="/tickets/new" element={<NewTicketProbe />} />
      </Routes>,
      { api, route: '/chat' },
    )

    // Question sans réponse → "je ne sais pas" (US02-AC4), escalade mise en avant (US10-AC1).
    await user.type(screen.getByLabelText(/votre message/i), 'question totalement inconnue zzz')
    await user.click(screen.getByRole('button', { name: /envoyer/i }))

    // Une bannière d'escalade apparaît avec un bouton "Créer un ticket".
    const escalate = await screen.findByRole('button', { name: /^créer un ticket$/i })
    await user.click(escalate)

    const prefill = await screen.findByTestId('prefill')
    await waitFor(() => {
      const value = JSON.parse(prefill.textContent || '{}')
      expect(value.title).toContain('question totalement inconnue')
      expect(value.description).toContain('question totalement inconnue')
    })
  })
})
