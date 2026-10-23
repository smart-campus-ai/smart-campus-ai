import { useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Skeleton } from '@/components/ui/skeleton'
import { StatusBadge, PriorityBadge, formatDate } from '@/components/common/badges'
import { FilterTags } from '@/components/common/FilterTags'
import { TICKET_STATUSES } from '@/domain/models'
import type { TicketListParams, TicketStatus } from '@/domain/models'
import { useTickets } from '@/hooks/queries'

const STATUS_OPTIONS: { value: TicketStatus | ''; label: string }[] = [
  { value: '', label: 'Tous' },
  ...TICKET_STATUSES.map((s) => ({ value: s, label: s })),
]

export function AdminTicketsPage() {
  const [status, setStatus] = useState<'' | TicketStatus>('')

  const params: TicketListParams = {
    status: status || undefined,
    sort: 'createdAt:desc',
  }
  const { data, isLoading, isError } = useTickets(params)
  const items = data?.items ?? []

  return (
    <section className="space-y-6">
      <h1 className="text-2xl font-semibold tracking-tight">Tickets</h1>

      <FilterTags label="Statut" options={STATUS_OPTIONS} value={status} onChange={setStatus} />

      {isError && (
        <p role="alert" className="text-sm text-destructive">
          Impossible de charger les tickets.
        </p>
      )}

      {isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
        </div>
      ) : items.length > 0 ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Réf.</TableHead>
              <TableHead>Titre</TableHead>
              <TableHead>Statut</TableHead>
              <TableHead>Priorité</TableHead>
              <TableHead>Créé le</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {items.map((t) => (
              <TableRow key={t.id}>
                <TableCell className="font-mono text-xs">{t.id}</TableCell>
                <TableCell>
                  <Link
                    to={`/admin/tickets/${t.id}`}
                    className="font-medium underline-offset-4 hover:underline"
                  >
                    {t.title}
                  </Link>
                </TableCell>
                <TableCell>
                  <StatusBadge status={t.status} />
                </TableCell>
                <TableCell>
                  <PriorityBadge priority={t.priority} />
                </TableCell>
                <TableCell className="text-muted-foreground">{formatDate(t.createdAt)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <p className="text-sm text-muted-foreground">Aucun ticket.</p>
      )}
    </section>
  )
}
