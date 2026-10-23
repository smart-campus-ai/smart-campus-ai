import { describe, expect, it } from 'vitest'
import { Route, Routes } from 'react-router-dom'
import { screen } from '@testing-library/react'
import { TicketDetailPage } from '@/pages/TicketDetailPage'
import { MockApi } from '@/api/mock'
import { renderWithProviders } from '@/test/render'

describe('US03 — détail de ticket (UI)', () => {
  it('US03-AC5 BOLA — le détail d’un ticket d’un autre étudiant affiche "introuvable"', async () => {
    // student-001 ouvre un ticket qui appartient à student-002.
    const api = new MockApi({ sub: 'student-001', email: 'alice@esiea.fr', role: 'student' })

    renderWithProviders(
      <Routes>
        <Route path="/tickets/:ticketId" element={<TicketDetailPage />} />
      </Routes>,
      { api, route: '/tickets/TCK0000000000000000002001' },
    )

    expect(await screen.findByText(/ticket introuvable/i)).toBeInTheDocument()
    // Aucune donnée du ticket de B n’est affichée.
    expect(screen.queryByText(/accès au labo/i)).not.toBeInTheDocument()
  })

  it('US03-AC2 — l’étudiant propriétaire voit le détail de son ticket', async () => {
    const api = new MockApi({ sub: 'student-001', email: 'alice@esiea.fr', role: 'student' })

    renderWithProviders(
      <Routes>
        <Route path="/tickets/:ticketId" element={<TicketDetailPage />} />
      </Routes>,
      { api, route: '/tickets/TCK0000000000000000001001' },
    )

    expect(await screen.findByText(/wi-fi indisponible/i)).toBeInTheDocument()
  })
})
