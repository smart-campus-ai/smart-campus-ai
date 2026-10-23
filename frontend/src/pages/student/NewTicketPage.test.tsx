import { describe, expect, it, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { NewTicketPage } from '@/pages/student/NewTicketPage'
import { MockApi } from '@/api/mock'
import { renderWithProviders } from '@/test/render'

describe('US04 — création d’un ticket (UI)', () => {
  it('US04-AC3 bloque la soumission et affiche un message quand les champs obligatoires sont vides', async () => {
    const api = new MockApi({ sub: 'student-001', email: 'alice@esiea.fr', role: 'student' })
    const createSpy = vi.spyOn(api, 'createTicket')
    const user = userEvent.setup()

    renderWithProviders(<NewTicketPage />, { api })

    await user.click(screen.getByRole('button', { name: /créer le ticket/i }))

    // Message d’erreur annoncé et aucun appel API.
    expect(await screen.findByText(/le titre est obligatoire/i)).toBeInTheDocument()
    expect(createSpy).not.toHaveBeenCalled()
  })

  it('US04-AC2 envoie les champs saisis à l’API quand le formulaire est valide', async () => {
    const api = new MockApi({ sub: 'student-001', email: 'alice@esiea.fr', role: 'student' })
    const createSpy = vi.spyOn(api, 'createTicket')
    const user = userEvent.setup()

    renderWithProviders(<NewTicketPage />, { api })

    await user.type(screen.getByLabelText(/titre/i), 'Projecteur HS')
    await user.selectOptions(screen.getByLabelText(/catégorie/i), 'incident')
    await user.type(screen.getByLabelText(/description/i), 'Le projecteur ne démarre pas.')
    await user.click(screen.getByRole('button', { name: /créer le ticket/i }))

    await waitFor(() => expect(createSpy).toHaveBeenCalledTimes(1))
    expect(createSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        title: 'Projecteur HS',
        description: 'Le projecteur ne démarre pas.',
        category: 'incident',
      }),
    )
  })
})
