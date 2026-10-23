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
import { TICKET_STATUSES } from '@/domain/models'
import type { TicketListParams, TicketStatus } from '@/domain/models'
import { useTickets } from '@/hooks/queries'

export function AdminTicketsPage() {
  const [status, setStatus] = useState<'' | TicketStatus>('')

  const params: TicketListParams = {
    status: status || undefined,
    sort: 'createdAt:desc',
  }
  const { data, isLoading, isError } = useTickets(params)
  const items = data?.items ?? []

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-semibold">Tickets</h1>

      <div className="flex flex-col gap-1">
        <label htmlFor="admin-filter-status" className="text-sm font-medium">
          Filtrer par statut
        </label>
        <select
          id="admin-filter-status"
          className="h-8 w-56 rounded-md border border-input bg-background px-2 text-sm"
          value={status}
          onChange={(e) => setStatus(e.target.value as '' | TicketStatus)}
        >
          <option value="">Tous les statuts actifs</option>
          {TICKET_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </div>

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
