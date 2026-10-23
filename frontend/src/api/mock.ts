import { ApiError } from '@/domain/api'
import type { ApiClient } from '@/domain/api'
import {
  CLOSING_STATUSES,
  type AttachmentUploadInput,
  type AuditEvent,
  type ChatMessage,
  type ChatSendInput,
  type ChatSession,
  type ChatSessionPage,
  type KpiParams,
  type KpiResponse,
  type Note,
  type PresignedUpload,
  type Role,
  type SendMessageResponse,
  type Ticket,
  type TicketCreateInput,
  type TicketDetail,
  type TicketListParams,
  type TicketPage,
  type TicketReplyInput,
  type TicketUpdateInput,
  type TrendPoint,
} from '@/domain/models'

/** Identity the mock uses to enforce ownership exactly like the real backend. */
export interface MockIdentity {
  sub: string
  email: string
  role: Role
}

let seq = 0
/** Pseudo-ULID so ids look like the contract (26 Crockford base32 chars). */
function ulid(): string {
  seq += 1
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
  let out = ''
  for (let i = 0; i < 26; i += 1) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)]
  }
  return out.slice(0, 20) + String(seq).padStart(6, '0')
}

function nowIso(offsetMs = 0): string {
  return new Date(Date.now() + offsetMs).toISOString()
}

interface MockTicket extends TicketDetail {
  ownerSub: string
}

function seedTickets(): MockTicket[] {
  return [
    {
      id: 'TCK0000000000000000001001',
      title: 'Wi-Fi indisponible en salle 204',
      description: "Impossible de se connecter au réseau eduroam depuis ce matin.",
      status: 'Ouvert',
      category: 'incident',
      priority: 'normale',
      ownerSub: 'student-001',
      location: 'Bâtiment A — salle 204',
      createdAt: nowIso(-3 * 86400000),
      updatedAt: nowIso(-3 * 86400000),
      notes: [],
      attachments: [],
      history: [
        { at: nowIso(-3 * 86400000), actorSub: 'student-001', field: 'status', oldValue: null, newValue: 'Ouvert' },
      ],
    },
    {
      id: 'TCK0000000000000000001002',
      title: 'Porte de la bibliothèque forcée',
      description: 'La porte latérale semble avoir été forcée pendant la nuit.',
      status: 'En cours',
      category: 'sécurité',
      priority: 'critique',
      ownerSub: 'student-001',
      assigneeSub: 'admin-001',
      location: 'Bibliothèque',
      createdAt: nowIso(-86400000),
      updatedAt: nowIso(-3600000),
      notes: [
        {
          id: ulid(),
          body: 'Intervention de la sécurité planifiée.',
          audience: 'student',
          authorRole: 'admin',
          createdAt: nowIso(-3600000),
        },
      ],
      attachments: [],
      history: [
        { at: nowIso(-86400000), actorSub: 'student-001', field: 'status', oldValue: null, newValue: 'Ouvert' },
        { at: nowIso(-3600000), actorSub: 'admin-001', field: 'status', oldValue: 'Ouvert', newValue: 'En cours' },
      ],
    },
    {
      id: 'TCK0000000000000000002001',
      title: "Demande d'accès au labo",
      description: "Besoin d'un accès au laboratoire réseau pour un projet.",
      status: 'En attente étudiant',
      category: 'besoin',
      priority: 'basse',
      ownerSub: 'student-002', // another student — BOLA target
      assigneeSub: 'admin-001',
      location: 'Labo réseau',
      createdAt: nowIso(-5 * 86400000),
      updatedAt: nowIso(-2 * 86400000),
      notes: [],
      attachments: [],
      history: [],
    },
    {
      id: 'TCK0000000000000000001003',
      title: 'Remboursement de frais de mission',
      description: 'Demande de remboursement pour un déplacement pédagogique.',
      status: 'En attente étudiant',
      category: 'besoin',
      priority: 'normale',
      ownerSub: 'student-001',
      assigneeSub: 'admin-001',
      location: 'Scolarité',
      createdAt: nowIso(-4 * 86400000),
      updatedAt: nowIso(-86400000),
      notes: [
        {
          id: ulid(),
          body: 'Merci de nous transmettre la facture correspondante pour traiter la demande.',
          audience: 'student',
          authorRole: 'admin',
          createdAt: nowIso(-86400000),
        },
      ],
      attachments: [],
      history: [
        { at: nowIso(-4 * 86400000), actorSub: 'student-001', field: 'status', oldValue: null, newValue: 'Ouvert' },
        { at: nowIso(-86400000), actorSub: 'admin-001', field: 'status', oldValue: 'En cours', newValue: 'En attente étudiant' },
      ],
    },
  ]
}

function toSummary(t: MockTicket): Ticket {
  return {
    id: t.id,
    title: t.title,
    category: t.category,
    status: t.status,
    priority: t.priority,
    location: t.location ?? null,
    ownerSub: t.ownerSub,
    assigneeSub: t.assigneeSub,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
  }
}

function buildKpi(tickets: MockTicket[], params: KpiParams): KpiResponse {
  const trend: TrendPoint[] = []
  const days = 14
  for (let i = days - 1; i >= 0; i -= 1) {
    trend.push({
      bucket: new Date(Date.now() - i * 86400000).toISOString().slice(0, 10),
      created: (i % 3) + 1,
      resolved: i % 2,
    })
  }
  const open = tickets.filter((t) => t.status !== 'Résolu' && t.status !== 'Fermé').length
  const resolved = tickets.filter((t) => t.status === 'Résolu' || t.status === 'Fermé').length
  return {
    range: { from: params.from, to: params.to },
    granularity: params.granularity ?? 'day',
    summary: {
      totalTickets: tickets.length,
      openTickets: open,
      resolvedTickets: resolved,
      averageResolutionSeconds: resolved > 0 ? 64800 : null,
    },
    trend,
  }
}

const UNRESOLVED_HINT =
  "je ne sais pas. Je n'ai pas trouvé d'information fiable dans la base de connaissances du campus."

/**
 * In-memory implementation of {@link ApiClient} enforcing the same security
 * rules as the backend (BOLA 404, admin 403, resolution note 400) so the SPA
 * is fully usable and testable offline, following packages/contracts.
 */
export class MockApi implements ApiClient {
  private tickets: MockTicket[]
  private sessions = new Map<string, ChatSession>()
  private identity: MockIdentity

  constructor(identity: MockIdentity) {
    this.identity = identity
    this.tickets = seedTickets()
  }

  setIdentity(identity: MockIdentity): void {
    this.identity = identity
  }

  private requireAdmin(): void {
    if (this.identity.role !== 'admin') {
      throw new ApiError(403, 'Réservé aux administrateurs.', 'forbidden')
    }
  }

  async listTickets(params: TicketListParams = {}): Promise<TicketPage> {
    await delay()
    let rows = this.tickets
    if (this.identity.role === 'student') {
      rows = rows.filter((t) => t.ownerSub === this.identity.sub)
    }
    if (params.status) rows = rows.filter((t) => t.status === params.status)
    if (params.category) rows = rows.filter((t) => t.category === params.category)

    const order = params.sort === 'createdAt:asc' ? 'asc' : 'desc'
    rows = [...rows].sort((a, b) => {
      const cmp = a.createdAt.localeCompare(b.createdAt)
      return order === 'asc' ? cmp : -cmp
    })
    return { items: rows.map(toSummary), nextCursor: null }
  }

  async getTicket(ticketId: string): Promise<TicketDetail> {
    await delay()
    const ticket = this.tickets.find((t) => t.id === ticketId)
    if (
      !ticket ||
      (this.identity.role === 'student' && ticket.ownerSub !== this.identity.sub)
    ) {
      throw new ApiError(404, 'Ticket introuvable.', 'not_found')
    }
    if (this.identity.role === 'student') {
      // Students never receive the audit trail nor internal notes.
      const { history: _history, ...rest } = ticket
      return { ...rest, notes: ticket.notes.filter((n) => n.audience === 'student') }
    }
    return ticket
  }

  async createTicket(input: TicketCreateInput): Promise<Ticket> {
    await delay()
    const isSecurity = input.category === 'sécurité'
    const createdAt = nowIso()
    const ticket: MockTicket = {
      id: ulid(),
      title: input.title,
      description: input.location
        ? `${input.description}\n\nLocalisation : ${input.location}`
        : input.description,
      status: 'Ouvert', // US04-AC4
      category: input.category,
      priority: isSecurity ? 'critique' : 'normale', // US04-AC5
      ownerSub: this.identity.sub, // US04-AC4 — owner is the JWT sub
      location: input.location ?? null,
      createdAt,
      updatedAt: createdAt,
      notes: [],
      attachments: [],
      history: [
        { at: createdAt, actorSub: this.identity.sub, field: 'status', oldValue: null, newValue: 'Ouvert' },
      ],
    }
    this.tickets = [ticket, ...this.tickets]
    return toSummary(ticket)
  }

  async updateTicket(ticketId: string, input: TicketUpdateInput): Promise<TicketDetail> {
    await delay()
    this.requireAdmin() // US01-AC6
    const ticket = this.tickets.find((t) => t.id === ticketId)
    if (!ticket) throw new ApiError(404, 'Ticket introuvable.', 'not_found')

    // US01-AC5 — a resolution note is required to move to "Résolu"/"Fermé".
    if (input.status && CLOSING_STATUSES.includes(input.status) && !input.note?.body?.trim()) {
      throw new ApiError(
        400,
        'Une note de résolution est obligatoire pour clôturer un ticket.',
        'validation_error',
      )
    }

    const stamp = nowIso()
    const events: AuditEvent[] = []
    const record = (field: AuditEvent['field'], oldValue: string | null, newValue: string | null) => {
      events.push({ at: stamp, actorSub: this.identity.sub, field, oldValue, newValue })
    }

    if (input.status && input.status !== ticket.status) {
      record('status', ticket.status, input.status)
      ticket.status = input.status
    }
    if (input.assigneeSub !== undefined && input.assigneeSub !== ticket.assigneeSub) {
      record('assignee', ticket.assigneeSub ?? null, input.assigneeSub)
      ticket.assigneeSub = input.assigneeSub
    }
    if (input.priority && input.priority !== ticket.priority) {
      record('priority', ticket.priority, input.priority)
      ticket.priority = input.priority
    }
    if (input.note?.body?.trim()) {
      const note: Note = {
        id: ulid(),
        body: input.note.body.trim(),
        audience: input.note.audience,
        authorRole: 'admin',
        createdAt: stamp,
      }
      ticket.notes = [...ticket.notes, note]
      record('note', null, note.body)
    }

    // US01-AC3 — audit events are only ever appended.
    ticket.history = [...(ticket.history ?? []), ...events]
    ticket.updatedAt = stamp
    return ticket
  }

  async replyToTicket(ticketId: string, input: TicketReplyInput): Promise<TicketDetail> {
    await delay()
    const ticket = this.tickets.find((t) => t.id === ticketId)
    // Owner-only; a student may only reply to their own ticket (BOLA → 404).
    if (
      !ticket ||
      (this.identity.role === 'student' && ticket.ownerSub !== this.identity.sub)
    ) {
      throw new ApiError(404, 'Ticket introuvable.', 'not_found')
    }
    // US03 — a reply is only expected while the ticket waits for the student.
    if (ticket.status !== 'En attente étudiant') {
      throw new ApiError(
        400,
        "Ce ticket n'attend pas de réponse de votre part.",
        'validation_error',
      )
    }

    const stamp = nowIso()
    const note: Note = {
      id: ulid(),
      body: input.body.trim(),
      audience: 'student',
      authorRole: 'student',
      createdAt: stamp,
    }
    ticket.notes = [...ticket.notes, note]
    // The student answered: hand the ticket back to the support team.
    ticket.history = [
      ...(ticket.history ?? []),
      { at: stamp, actorSub: this.identity.sub, field: 'note', oldValue: null, newValue: note.body },
      { at: stamp, actorSub: this.identity.sub, field: 'status', oldValue: 'En attente étudiant', newValue: 'En cours' },
    ]
    ticket.status = 'En cours'
    ticket.updatedAt = stamp

    // Return the student-facing projection (no audit trail, student notes only).
    const { history: _history, ...rest } = ticket
    return { ...rest, notes: ticket.notes.filter((n) => n.audience === 'student') }
  }

  async createAttachmentUpload(
    ticketId: string,
    input: AttachmentUploadInput,
  ): Promise<PresignedUpload> {
    await delay()
    const ticket = this.tickets.find((t) => t.id === ticketId)
    if (!ticket || (this.identity.role === 'student' && ticket.ownerSub !== this.identity.sub)) {
      throw new ApiError(404, 'Ticket introuvable.', 'not_found')
    }
    return {
      attachmentId: ulid(),
      url: 'https://example-attachments.s3.amazonaws.com/',
      fields: {
        key: `tickets/${ticketId}/${input.filename}`,
        'Content-Type': input.contentType,
      },
      expiresAt: nowIso(15 * 60 * 1000),
    }
  }

  async sendChatMessage(input: ChatSendInput): Promise<SendMessageResponse> {
    await delay()
    const sessionId = input.sessionId ?? ulid()
    const existing = this.sessions.get(sessionId)
    const createdAt = existing?.createdAt ?? nowIso()

    const userMessage: ChatMessage = {
      id: ulid(),
      role: 'user',
      content: input.message,
      createdAt: nowIso(),
    }

    const known = /wifi|wi-fi|biblioth|horaire|inscription|scolarit/i.test(input.message)
    const answered = known
    const reply: ChatMessage = known
      ? {
          id: ulid(),
          role: 'assistant',
          content:
            "D'après le guide du campus, le Wi-Fi eduroam est accessible avec vos identifiants ESIEA ; la bibliothèque est ouverte de 8h à 20h en semaine.",
          createdAt: nowIso(),
          sources: [
            { title: 'Guide du campus — Connectivité', uri: 'kb://campus/wifi' },
            { title: 'Horaires des services', uri: 'kb://campus/horaires' },
          ],
        }
      : {
          id: ulid(),
          role: 'assistant',
          content: UNRESOLVED_HINT,
          createdAt: nowIso(),
        }

    const messages = [...(existing?.messages ?? []), userMessage, reply]
    const stamp = nowIso()
    this.sessions.set(sessionId, {
      id: sessionId,
      ownerSub: this.identity.sub,
      messages,
      createdAt,
      updatedAt: stamp,
    })

    // US10 — on failure to answer, surface a prefilled ticket draft.
    const ticketSuggestion = answered
      ? null
      : {
          title: input.message.slice(0, 80),
          description: messages
            .map((m) => `${m.role === 'user' ? 'Moi' : 'Assistant'} : ${m.content}`)
            .join('\n'),
        }

    return { sessionId, reply, answered, ticketSuggestion }
  }

  async listChatSessions(): Promise<ChatSessionPage> {
    await delay()
    const items = [...this.sessions.values()]
      .filter((s) => s.ownerSub === this.identity.sub)
      .map((s) => ({
        id: s.id,
        title: s.messages[0]?.content.slice(0, 60) ?? null,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
      }))
    return { items, nextCursor: null }
  }

  async getChatSession(sessionId: string): Promise<ChatSession> {
    await delay()
    const session = this.sessions.get(sessionId)
    // US02-AC6 — a session owned by someone else is 404.
    if (!session || session.ownerSub !== this.identity.sub) {
      throw new ApiError(404, 'Session introuvable.', 'not_found')
    }
    return session
  }

  async deleteChatHistory(): Promise<void> {
    await delay()
    // US08-AC2/AC3 — only the caller's own sessions are cleared.
    for (const [id, session] of this.sessions) {
      if (session.ownerSub === this.identity.sub) this.sessions.delete(id)
    }
  }

  async getKpi(params: KpiParams): Promise<KpiResponse> {
    await delay()
    this.requireAdmin() // US05-AC5
    return buildKpi(this.tickets, params)
  }
}

/** Small artificial latency so loading/skeleton states are exercised. */
function delay(ms = 80): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
