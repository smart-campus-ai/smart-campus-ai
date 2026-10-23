import { z } from 'zod'

/**
 * Domain model for SmartCampus AI, aligned 1:1 with the official contract in
 * packages/contracts (openapi.yaml + schemas/*.json). Field names, enums and
 * pagination mirror the JSON Schemas so the SPA, the handlers and the API
 * Gateway models stay in sync.
 */

/* --------------------------------------------------------------- Common */

/** common.json Error.code enum. */
export const ERROR_CODES = [
  'validation_error',
  'unauthorized',
  'forbidden',
  'not_found',
  'conflict',
  'rate_limited',
  'internal_error',
] as const
export type ErrorCode = (typeof ERROR_CODES)[number]

export interface ErrorDetail {
  field: string
  issue: string
}

/** common.json Error envelope. */
export interface ApiErrorBody {
  code: ErrorCode
  message: string
  details?: ErrorDetail[]
  requestId?: string
}

/** common.json Page — cursor pagination envelope shared by list responses. */
export interface Page<T> {
  items: T[]
  nextCursor: string | null
}

/* --------------------------------------------------------------- Ticket */

/** US03 — the five reference statuses of the whole platform. */
export const TICKET_STATUSES = [
  'Ouvert',
  'En cours',
  'En attente étudiant',
  'Résolu',
  'Fermé',
] as const
export type TicketStatus = (typeof TICKET_STATUSES)[number]

/** US01-AC5 — statuses that require a resolution note before they can be set. */
export const CLOSING_STATUSES: readonly TicketStatus[] = ['Résolu', 'Fermé']

/** ticket.json TicketCategory (working set, PO to confirm). */
export const TICKET_CATEGORIES = ['besoin', 'incident', 'sécurité'] as const
export type TicketCategory = (typeof TICKET_CATEGORIES)[number]

/** ticket.json TicketPriority (includes 'critique', US01-AC2). */
export const TICKET_PRIORITIES = ['basse', 'normale', 'haute', 'critique'] as const
export type TicketPriority = (typeof TICKET_PRIORITIES)[number]

/** Cognito groups. */
export const ROLES = ['student', 'admin'] as const
export type Role = (typeof ROLES)[number]

/** ticket.json Note.audience / note author role. */
export type NoteAudience = 'student' | 'internal'
export type AuthorRole = 'student' | 'admin'

export interface Note {
  id: string
  body: string
  audience: NoteAudience
  authorRole: AuthorRole
  createdAt: string
}

/** ticket.json Attachment. */
export type AttachmentStatus = 'pending' | 'clean' | 'infected'
export interface Attachment {
  id: string
  filename: string
  contentType: 'image/jpeg' | 'image/png'
  size: number
  status: AttachmentStatus
}

/** ticket.json AuditEvent — immutable (US01-AC3). */
export const AUDIT_FIELDS = [
  'status',
  'assignee',
  'priority',
  'note',
  'escalation',
] as const
export type AuditField = (typeof AUDIT_FIELDS)[number]

export interface AuditEvent {
  at: string
  actorSub: string
  field: AuditField
  oldValue: string | null
  newValue: string | null
}

/** ticket.json Ticket — summary shape used in lists and on creation. */
export interface Ticket {
  id: string
  title: string
  category: TicketCategory
  status: TicketStatus
  priority: TicketPriority
  location?: string | null
  ownerSub: string
  assigneeSub?: string
  createdAt: string
  updatedAt: string
}

/** ticket.json TicketDetail — full ticket with history and attachments. */
export interface TicketDetail extends Ticket {
  description: string
  notes: Note[]
  attachments: Attachment[]
  /** Audit trail, present for admins (US01-AC3). */
  history?: AuditEvent[]
}

export type TicketPage = Page<Ticket>

/**
 * US04 — CreateTicketRequest. title/category/description required, location
 * optional. Owner/status/priority/id are server-assigned.
 */
export const ticketCreateSchema = z.object({
  title: z
    .string()
    .trim()
    .min(1, 'Le titre est obligatoire.')
    .max(140, 'Le titre ne doit pas dépasser 140 caractères.'),
  category: z.enum(TICKET_CATEGORIES, {
    message: 'La catégorie est obligatoire.',
  }),
  description: z
    .string()
    .trim()
    .min(1, 'La description est obligatoire.')
    .max(5000, 'La description ne doit pas dépasser 5000 caractères.'),
  location: z.string().trim().max(140).optional(),
})
export type TicketCreateInput = z.infer<typeof ticketCreateSchema>

/**
 * US01 — UpdateTicketRequest. At least one field; note is an object
 * {body, audience}. The resolution note is sent as a student-facing note when
 * closing; the handler enforces its presence (400 otherwise).
 */
export const ticketUpdateSchema = z
  .object({
    status: z.enum(TICKET_STATUSES).optional(),
    priority: z.enum(TICKET_PRIORITIES).optional(),
    assigneeSub: z.string().max(128).optional(),
    note: z
      .object({
        body: z.string().min(1).max(4000),
        audience: z.enum(['student', 'internal']),
      })
      .optional(),
  })
  .refine((v) => Object.values(v).some((x) => x !== undefined), {
    message: 'Au moins un champ doit être renseigné.',
  })
export type TicketUpdateInput = z.infer<typeof ticketUpdateSchema>

/**
 * US03 — student reply when a ticket is "En attente étudiant". The student
 * provides the information the admin is waiting for; this is not yet an
 * endpoint in packages/contracts (needs a `contracts` PR: POST
 * /tickets/{id}/comments, author = JWT sub, audience student).
 */
export const ticketReplySchema = z.object({
  body: z
    .string()
    .trim()
    .min(1, 'Votre réponse ne peut pas être vide.')
    .max(4000, 'La réponse ne doit pas dépasser 4000 caractères.'),
})
export type TicketReplyInput = z.infer<typeof ticketReplySchema>

/** List query parameters (contract: single `sort` string + cursor pagination). */
export interface TicketListParams {
  status?: TicketStatus
  category?: TicketCategory
  sort?: 'createdAt:asc' | 'createdAt:desc'
  limit?: number
  cursor?: string
}

/* ------------------------------------------------------------ Attachment */

export const attachmentUploadSchema = z.object({
  filename: z.string().min(1).max(255),
  contentType: z.enum(['image/jpeg', 'image/png']),
  size: z.number().int().min(1).max(10 * 1024 * 1024),
})
export type AttachmentUploadInput = z.infer<typeof attachmentUploadSchema>

export interface PresignedUpload {
  attachmentId: string
  url: string
  fields: Record<string, string>
  expiresAt?: string
}

/* ------------------------------------------------------------------ Chat */

export interface ChatSource {
  title: string
  uri?: string | null
}

export interface ChatMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  sources?: ChatSource[]
  createdAt: string
}

export interface ChatSessionSummary {
  id: string
  title?: string | null
  createdAt: string
  updatedAt: string
}

export interface ChatSession {
  id: string
  ownerSub: string
  messages: ChatMessage[]
  createdAt: string
  updatedAt: string
}

export type ChatSessionPage = Page<ChatSessionSummary>

/** chat.json SendMessageRequest (message 1..4000). */
export const chatSendSchema = z.object({
  sessionId: z.string().optional(),
  message: z
    .string()
    .trim()
    .min(1, 'Le message ne peut pas être vide.')
    .max(4000, 'Le message ne doit pas dépasser 4000 caractères.'),
})
export type ChatSendInput = z.infer<typeof chatSendSchema>

/** chat.json SendMessageResponse. */
export interface SendMessageResponse {
  sessionId: string
  reply: ChatMessage
  /** RF03 — false when the assistant said "je ne sais pas" (US10 escalation). */
  answered: boolean
  /** US10-AC2 — prefilled ticket draft offered on escalation. */
  ticketSuggestion?: { title?: string; description?: string } | null
}

/* ------------------------------------------------------------------- KPI */

/** kpi.json KpiSummary. */
export interface KpiSummary {
  totalTickets: number
  openTickets: number
  resolvedTickets: number
  averageResolutionSeconds: number | null
}

/** kpi.json TrendPoint. */
export interface TrendPoint {
  bucket: string
  created: number
  resolved: number
}

/** kpi.json KpiResponse. */
export interface KpiResponse {
  range: { from: string; to: string }
  granularity: 'day' | 'week' | 'month'
  summary: KpiSummary
  trend: TrendPoint[]
}

/** US05 — KPI query parameters (from/to are required by the contract). */
export interface KpiParams {
  from: string
  to: string
  status?: TicketStatus
  category?: TicketCategory
  granularity?: 'day' | 'week' | 'month'
}
