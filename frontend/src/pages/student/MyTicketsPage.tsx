import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
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

export function MyTicketsPage() {
  const [status, setStatus] = useState<'' | TicketStatus>('')
  const [order, setOrder] = useState<'asc' | 'desc'>('desc')

  const params: TicketListParams = {
    status: status || undefined,
    sort: order === 'asc' ? 'createdAt:asc' : 'createdAt:desc',
  }
  const { data, isLoading, isError } = useTickets(params)
  const items = data?.items ?? []

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">Mes tickets</h1>
        <Button render={<Link to="/tickets/new" />}>Nouveau ticket</Button>
      </div>

      <div className="flex flex-wrap items-end gap-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="filter-status" className="text-sm font-medium">
            Filtrer par statut
          </label>
          {/* Native select keeps the filter fully keyboard/screen-reader accessible (US03-AC4). */}
          <select
            id="filter-status"
            className="h-8 rounded-md border border-input bg-background px-2 text-sm"
            value={status}
            onChange={(e) => setStatus(e.target.value as '' | TicketStatus)}
          >
            <option value="">Tous</option>
            {TICKET_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="sort-order" className="text-sm font-medium">
            Trier par date de création
          </label>
          <select
            id="sort-order"
            className="h-8 rounded-md border border-input bg-background px-2 text-sm"
            value={order}
            onChange={(e) => setOrder(e.target.value as 'asc' | 'desc')}
          >
            <option value="desc">Plus récents d'abord</option>
            <option value="asc">Plus anciens d'abord</option>
          </select>
        </div>
      </div>

      {isError && (
        <p role="alert" className="text-sm text-destructive">
          Impossible de charger vos tickets.
        </p>
      )}

      {isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
        </div>
      ) : items.length > 0 ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Titre</TableHead>
              <TableHead>Statut</TableHead>
              <TableHead>Priorité</TableHead>
              <TableHead>Dernière mise à jour</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {items.map((t) => (
              <TableRow key={t.id}>
                <TableCell>
                  <Link to={`/tickets/${t.id}`} className="font-medium underline-offset-4 hover:underline">
                    {t.title}
                  </Link>
                </TableCell>
                <TableCell>
                  <StatusBadge status={t.status} />
                </TableCell>
                <TableCell>
                  <PriorityBadge priority={t.priority} />
                </TableCell>
                <TableCell className="text-muted-foreground">{formatDate(t.updatedAt)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <p className="text-sm text-muted-foreground">Aucun ticket pour le moment.</p>
      )}
    </section>
  )
}
