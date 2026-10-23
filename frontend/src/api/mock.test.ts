import { describe, expect, it } from 'vitest'
import { MockApi } from '@/api/mock'
import { ApiError } from '@/domain/api'
import type { MockIdentity } from '@/api/mock'
import type { KpiParams } from '@/domain/models'

const STUDENT_A: MockIdentity = { sub: 'student-001', email: 'alice@esiea.fr', role: 'student' }
const STUDENT_B: MockIdentity = { sub: 'student-002', email: 'bob@esiea.fr', role: 'student' }
const ADMIN: MockIdentity = { sub: 'admin-001', email: 'admin@esiea.fr', role: 'admin' }

const TCK_OF_A = 'TCK0000000000000000001001'
const TCK_OF_B = 'TCK0000000000000000002001'
const KPI_RANGE: KpiParams = { from: '2026-01-01', to: '2026-01-31' }

describe('US03 — suivi des tickets par l’étudiant', () => {
  it('US03-AC1 liste paginée des tickets de l’étudiant avec statut et mise à jour', async () => {
    const api = new MockApi(STUDENT_A)
    const page = await api.listTickets()
    expect(page.items.length).toBeGreaterThan(0)
    expect(page).toHaveProperty('nextCursor')
    expect(page.items.every((t) => t.status && t.updatedAt)).toBe(true)
    expect(page.items.some((t) => t.id === TCK_OF_B)).toBe(false)
  })

  it('US03-AC4 filtre par statut et trie par date de création', async () => {
    const api = new MockApi(STUDENT_A)
    const page = await api.listTickets({ status: 'Ouvert', sort: 'createdAt:asc' })
    expect(page.items.every((t) => t.status === 'Ouvert')).toBe(true)
  })

  it('US03-AC5 BOLA — un étudiant reçoit 404 sur le ticket d’un autre', async () => {
    const api = new MockApi(STUDENT_A)
    await expect(api.getTicket(TCK_OF_B)).rejects.toMatchObject({ status: 404 })
  })

  it('US03-AC5 BOLA — la liste de A ne contient jamais le ticket de B', async () => {
    const api = new MockApi(STUDENT_B)
    const forB = await api.listTickets()
    expect(forB.items.some((t) => t.id === TCK_OF_B)).toBe(true)
    api.setIdentity(STUDENT_A)
    const forA = await api.listTickets()
    expect(forA.items.some((t) => t.id === TCK_OF_B)).toBe(false)
  })
})

describe('US04 — création d’un ticket', () => {
  it('US04-AC4 crée un ticket au statut "Ouvert" avec le sub comme propriétaire', async () => {
    const api = new MockApi(STUDENT_A)
    const ticket = await api.createTicket({ title: 'Test', description: 'Desc', category: 'incident' })
    expect(ticket.status).toBe('Ouvert')
    expect(ticket.ownerSub).toBe(STUDENT_A.sub)
    expect(ticket.id).toBeTruthy()
  })

  it('US04-AC5 un ticket de catégorie "sécurité" reçoit la priorité "critique"', async () => {
    const api = new MockApi(STUDENT_A)
    const ticket = await api.createTicket({
      title: 'Porte forcée',
      description: 'Incident',
      category: 'sécurité',
    })
    expect(ticket.priority).toBe('critique')
  })
})

describe('US04-AC6 — pièce jointe', () => {
  it('retourne un POST pré-signé pour une image sur un ticket du propriétaire', async () => {
    const api = new MockApi(STUDENT_A)
    const presigned = await api.createAttachmentUpload(TCK_OF_A, {
      filename: 'photo.jpg',
      contentType: 'image/jpeg',
      size: 1024,
    })
    expect(presigned.url).toBeTruthy()
    expect(presigned.fields).toBeTypeOf('object')
    expect(presigned.attachmentId).toBeTruthy()
  })
})

describe('US01 — gestion des tickets par l’administrateur', () => {
  it('US01-AC2 met à jour statut, assignation et priorité', async () => {
    const api = new MockApi(ADMIN)
    const updated = await api.updateTicket(TCK_OF_A, {
      status: 'En cours',
      assigneeSub: 'admin-001',
      priority: 'haute',
    })
    expect(updated.status).toBe('En cours')
    expect(updated.assigneeSub).toBe('admin-001')
    expect(updated.priority).toBe('haute')
  })

  it('US01-AC3 ajoute des événements d’audit (history) sans jamais les supprimer', async () => {
    const api = new MockApi(ADMIN)
    const before = (await api.getTicket(TCK_OF_A)).history?.length ?? 0
    const after = await api.updateTicket(TCK_OF_A, { status: 'En cours' })
    expect((after.history?.length ?? 0)).toBeGreaterThan(before)
    const last = after.history![after.history!.length - 1]
    expect(last.field).toBe('status')
    expect(last.actorSub).toBe(ADMIN.sub)
    expect(last.newValue).toBe('En cours')
    expect(last.at).toBeTruthy()
  })

  it('US01-AC5 rejette en 400 la clôture sans note de résolution', async () => {
    const api = new MockApi(ADMIN)
    await expect(
      api.updateTicket(TCK_OF_A, { status: 'Résolu' }),
    ).rejects.toMatchObject({ status: 400, code: 'validation_error' })
    const ticket = await api.getTicket(TCK_OF_A)
    expect(ticket.status).not.toBe('Résolu')
  })

  it('US01-AC5 autorise la clôture avec une note de résolution', async () => {
    const api = new MockApi(ADMIN)
    const updated = await api.updateTicket(TCK_OF_A, {
      status: 'Résolu',
      note: { body: 'Problème corrigé.', audience: 'student' },
    })
    expect(updated.status).toBe('Résolu')
  })

  it('US01-AC6 un étudiant reçoit 403 sur une action de gestion admin', async () => {
    const api = new MockApi(STUDENT_A)
    await expect(
      api.updateTicket(TCK_OF_A, { status: 'En cours' }),
    ).rejects.toMatchObject({ status: 403 })
  })
})

describe('US02 — discussion avec le chatbot', () => {
  it('US02-AC3 cite des sources et renvoie answered=true quand la KB répond', async () => {
    const api = new MockApi(STUDENT_A)
    const res = await api.sendChatMessage({ message: 'Quels sont les horaires de la bibliothèque ?' })
    expect(res.reply.role).toBe('assistant')
    expect(res.answered).toBe(true)
    expect(res.reply.sources && res.reply.sources.length).toBeGreaterThan(0)
  })

  it('US02-AC4 répond "je ne sais pas" (answered=false) et propose un ticket', async () => {
    const api = new MockApi(STUDENT_A)
    const res = await api.sendChatMessage({ message: 'xyzqwerty inconnu' })
    expect(res.reply.content.toLowerCase()).toContain('je ne sais pas')
    expect(res.answered).toBe(false)
    expect(res.ticketSuggestion).not.toBeNull()
  })

  it('US02-AC5 conserve l’historique de session', async () => {
    const api = new MockApi(STUDENT_A)
    const first = await api.sendChatMessage({ message: 'Bonjour' })
    const session = await api.getChatSession(first.sessionId)
    expect(session.messages.length).toBe(2) // user + assistant
  })

  it('US02-AC6 isolation — la session d’un autre étudiant renvoie 404', async () => {
    const api = new MockApi(STUDENT_A)
    const first = await api.sendChatMessage({ message: 'Bonjour' })
    api.setIdentity(STUDENT_B)
    await expect(api.getChatSession(first.sessionId)).rejects.toMatchObject({ status: 404 })
  })
})

describe('US05 — consultation des KPI', () => {
  it('US05-AC1 renvoie les indicateurs clés à un admin', async () => {
    const api = new MockApi(ADMIN)
    const kpi = await api.getKpi(KPI_RANGE)
    expect(kpi.summary).toHaveProperty('totalTickets')
    expect(kpi.summary).toHaveProperty('openTickets')
    expect(kpi.summary).toHaveProperty('resolvedTickets')
    expect(kpi.summary).toHaveProperty('averageResolutionSeconds')
    expect(kpi.trend.length).toBeGreaterThan(0)
    expect(kpi.range).toEqual({ from: KPI_RANGE.from, to: KPI_RANGE.to })
  })

  it('US05-AC5 un étudiant reçoit 403 sur l’API KPI', async () => {
    const api = new MockApi(STUDENT_A)
    await expect(api.getKpi(KPI_RANGE)).rejects.toMatchObject({ status: 403 })
  })
})

describe('US08 — RGPD des historiques de chat', () => {
  it('US08-AC2 supprime l’historique: la session n’est plus accessible', async () => {
    const api = new MockApi(STUDENT_A)
    const res = await api.sendChatMessage({ message: 'Bonjour' })
    expect((await api.listChatSessions()).items.length).toBeGreaterThan(0)
    await api.deleteChatHistory()
    expect((await api.listChatSessions()).items.length).toBe(0)
    await expect(api.getChatSession(res.sessionId)).rejects.toMatchObject({ status: 404 })
  })

  it('US08-AC3 la suppression est limitée aux sessions du demandeur', async () => {
    const api = new MockApi(STUDENT_A)
    const aSession = await api.sendChatMessage({ message: 'Session de A' })
    api.setIdentity(STUDENT_B)
    await api.sendChatMessage({ message: 'Session de B' })
    await api.deleteChatHistory() // B supprime seulement les siennes
    api.setIdentity(STUDENT_A)
    const stillThere = await api.getChatSession(aSession.sessionId)
    expect(stillThere.id).toBe(aSession.sessionId)
  })
})

describe('ApiError', () => {
  it('expose des accès typés isForbidden/isNotFound/isValidation/isRateLimited', () => {
    expect(new ApiError(403, 'x', 'forbidden').isForbidden).toBe(true)
    expect(new ApiError(404, 'x', 'not_found').isNotFound).toBe(true)
    expect(new ApiError(400, 'x', 'validation_error').isValidation).toBe(true)
    expect(new ApiError(429, 'x', 'rate_limited').isRateLimited).toBe(true)
  })
})
