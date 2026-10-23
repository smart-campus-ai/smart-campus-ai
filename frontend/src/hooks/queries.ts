import {
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import { useApi } from '@/api/context'
import type {
  ChatSendInput,
  KpiParams,
  TicketCreateInput,
  TicketListParams,
  TicketUpdateInput,
} from '@/domain/models'

export function useTickets(params: TicketListParams = {}) {
  const api = useApi()
  return useQuery({
    queryKey: ['tickets', params],
    queryFn: () => api.listTickets(params),
  })
}

export function useTicket(ticketId: string | undefined) {
  const api = useApi()
  return useQuery({
    queryKey: ['ticket', ticketId],
    queryFn: () => api.getTicket(ticketId as string),
    enabled: Boolean(ticketId),
  })
}

export function useCreateTicket() {
  const api = useApi()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: TicketCreateInput) => api.createTicket(input),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

export function useUpdateTicket(ticketId: string) {
  const api = useApi()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: TicketUpdateInput) => api.updateTicket(ticketId, input),
    onSuccess: (ticket) => {
      qc.setQueryData(['ticket', ticketId], ticket)
      void qc.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

export function useSendChatMessage() {
  const api = useApi()
  return useMutation({
    mutationFn: (input: ChatSendInput) => api.sendChatMessage(input),
  })
}

export function useDeleteChatHistory() {
  const api = useApi()
  return useMutation({
    mutationFn: () => api.deleteChatHistory(),
  })
}

export function useKpi(params: KpiParams) {
  const api = useApi()
  return useQuery({
    queryKey: ['kpi', params],
    queryFn: () => api.getKpi(params),
  })
}
