import { config } from '@/lib/config'
import type { ApiClient } from '@/domain/api'
import { ApiError } from '@/domain/api'
import type {
  AttachmentUploadInput,
  ChatSendInput,
  ChatSession,
  ChatSessionPage,
  KpiParams,
  KpiResponse,
  PresignedUpload,
  SendMessageResponse,
  Ticket,
  TicketCreateInput,
  TicketDetail,
  TicketListParams,
  TicketPage,
  TicketUpdateInput,
} from '@/domain/models'

/** Supplies the current access token (JWT) for the Authorization header. */
export type TokenProvider = () => string | null

function buildQuery(params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== '') search.set(key, String(value))
  }
  const qs = search.toString()
  return qs ? `?${qs}` : ''
}

/**
 * Real API client for the regional REST API behind CloudFront (/api/*).
 * Same origin as the SPA (no CORS); the Cognito access token is sent as a
 * Bearer. Paths and payloads follow packages/contracts/openapi.yaml.
 */
export class HttpApi implements ApiClient {
  private readonly getToken: TokenProvider
  private readonly baseUrl: string

  constructor(getToken: TokenProvider, baseUrl: string = config.apiBaseUrl) {
    this.getToken = getToken
    this.baseUrl = baseUrl
  }

  private async request<T>(path: string, init?: RequestInit): Promise<T> {
    const token = this.getToken()
    const headers = new Headers(init?.headers)
    headers.set('Accept', 'application/json')
    if (init?.body) headers.set('Content-Type', 'application/json')
    if (token) headers.set('Authorization', `Bearer ${token}`)

    let response: Response
    try {
      response = await fetch(`${this.baseUrl}${path}`, { ...init, headers })
    } catch {
      throw new ApiError(0, 'Le service est injoignable. Réessayez plus tard.')
    }

    if (!response.ok) {
      // All non-2xx responses use the contract Error envelope {code, message}.
      let message = `Erreur ${response.status}`
      let code
      try {
        const body = await response.json()
        message = body.message ?? message
        code = body.code
      } catch {
        // response had no JSON body
      }
      throw new ApiError(response.status, message, code)
    }

    if (response.status === 204) return undefined as T
    return (await response.json()) as T
  }

  listTickets(params: TicketListParams = {}): Promise<TicketPage> {
    return this.request<TicketPage>(
      `/tickets${buildQuery({
        status: params.status,
        category: params.category,
        sort: params.sort,
        limit: params.limit,
        cursor: params.cursor,
      })}`,
    )
  }

  getTicket(ticketId: string): Promise<TicketDetail> {
    return this.request<TicketDetail>(`/tickets/${encodeURIComponent(ticketId)}`)
  }

  createTicket(input: TicketCreateInput): Promise<Ticket> {
    return this.request<Ticket>('/tickets', {
      method: 'POST',
      body: JSON.stringify(input),
    })
  }

  updateTicket(ticketId: string, input: TicketUpdateInput): Promise<TicketDetail> {
    return this.request<TicketDetail>(`/tickets/${encodeURIComponent(ticketId)}`, {
      method: 'PATCH',
      body: JSON.stringify(input),
    })
  }

  createAttachmentUpload(
    ticketId: string,
    input: AttachmentUploadInput,
  ): Promise<PresignedUpload> {
    return this.request<PresignedUpload>(
      `/tickets/${encodeURIComponent(ticketId)}/attachments`,
      { method: 'POST', body: JSON.stringify(input) },
    )
  }

  sendChatMessage(input: ChatSendInput): Promise<SendMessageResponse> {
    return this.request<SendMessageResponse>('/chat/messages', {
      method: 'POST',
      body: JSON.stringify(input),
    })
  }

  listChatSessions(params: { limit?: number; cursor?: string } = {}): Promise<ChatSessionPage> {
    return this.request<ChatSessionPage>(
      `/chat/sessions${buildQuery({ limit: params.limit, cursor: params.cursor })}`,
    )
  }

  getChatSession(sessionId: string): Promise<ChatSession> {
    return this.request<ChatSession>(`/chat/sessions/${encodeURIComponent(sessionId)}`)
  }

  deleteChatHistory(): Promise<void> {
    return this.request<void>('/chat/sessions', { method: 'DELETE' })
  }

  getKpi(params: KpiParams): Promise<KpiResponse> {
    return this.request<KpiResponse>(
      `/kpi${buildQuery({
        from: params.from,
        to: params.to,
        status: params.status,
        category: params.category,
        granularity: params.granularity,
      })}`,
    )
  }
}
