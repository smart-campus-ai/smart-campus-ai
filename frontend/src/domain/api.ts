import type {
  AttachmentUploadInput,
  ChatSendInput,
  ChatSession,
  ChatSessionPage,
  ErrorCode,
  KpiParams,
  KpiResponse,
  PresignedUpload,
  SendMessageResponse,
  Ticket,
  TicketCreateInput,
  TicketDetail,
  TicketListParams,
  TicketPage,
  TicketReplyInput,
  TicketUpdateInput,
} from './models'

/** Typed API error carrying the HTTP status + contract error code. */
export class ApiError extends Error {
  readonly status: number
  readonly code?: ErrorCode

  constructor(status: number, message: string, code?: ErrorCode) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }

  get isForbidden(): boolean {
    return this.status === 403
  }

  /** US03-AC5 / US02-AC6 — a resource owned by someone else is reported as 404. */
  get isNotFound(): boolean {
    return this.status === 404
  }

  get isValidation(): boolean {
    return this.status === 400
  }

  get isRateLimited(): boolean {
    return this.status === 429
  }
}

/**
 * The contract the UI depends on, mirroring packages/contracts/openapi.yaml.
 * Two implementations: HttpApi (real) and MockApi (in-memory, VITE_USE_MOCKS).
 */
export interface ApiClient {
  // Tickets — student scope is enforced server-side from the JWT sub.
  listTickets(params?: TicketListParams): Promise<TicketPage>
  getTicket(ticketId: string): Promise<TicketDetail>
  createTicket(input: TicketCreateInput): Promise<Ticket>
  updateTicket(ticketId: string, input: TicketUpdateInput): Promise<TicketDetail>
  /** US03 — student reply when a ticket is "En attente étudiant". */
  replyToTicket(ticketId: string, input: TicketReplyInput): Promise<TicketDetail>

  // Attachments (US04-AC6)
  createAttachmentUpload(
    ticketId: string,
    input: AttachmentUploadInput,
  ): Promise<PresignedUpload>

  // Chat
  sendChatMessage(input: ChatSendInput): Promise<SendMessageResponse>
  listChatSessions(params?: { limit?: number; cursor?: string }): Promise<ChatSessionPage>
  getChatSession(sessionId: string): Promise<ChatSession>
  /** US08 — delete all chat history of the authenticated student. */
  deleteChatHistory(): Promise<void>

  // KPI (admin only, 403 for students — US05-AC5)
  getKpi(params: KpiParams): Promise<KpiResponse>
}
