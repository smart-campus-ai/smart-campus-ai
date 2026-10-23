import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Card, CardContent } from '@/components/ui/card'
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
import { NewTicketDialog } from './NewTicketDialog'

export function MyTicketsPage() {
  const navigate = useNavigate()
  const [status, setStatus] = useState<'' | TicketStatus>('')
  const [order, setOrder] = useState<'asc' | 'desc'>('desc')

  const params: TicketListParams = {
    status: status || undefined,
    sort: order === 'asc' ? 'createdAt:asc' : 'createdAt:desc',
  }
  const { data, isLoading, isError } = useTickets(params)
  const items = data?.items ?? []

  return (
    <section className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Mes tickets</h1>
          <p className="text-sm text-muted-foreground">
            Suivez l'avancement de vos demandes de support.
          </p>
        </div>
        <NewTicketDialog onCreated={(t) => navigate(`/tickets/${t.id}`)} />
      </div>

      <div className="flex flex-wrap items-end gap-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="filter-status" className="text-sm font-medium">
            Statut
          </label>
          {/* Native select keeps the filter fully keyboard/screen-reader accessible (US03-AC4). */}
          <select
            id="filter-status"
            className="h-9 rounded-md border border-input bg-background px-2.5 text-sm"
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
            Tri
          </label>
          <select
            id="sort-order"
            className="h-9 rounded-md border border-input bg-background px-2.5 text-sm"
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
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      ) : items.length > 0 ? (
        <Card className="overflow-hidden p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Titre</TableHead>
                <TableHead>Statut</TableHead>
                <TableHead>Priorité</TableHead>
                <TableHead className="text-right">Dernière mise à jour</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((t) => (
                <TableRow key={t.id} className="cursor-pointer">
                  <TableCell>
                    <Link
                      to={`/tickets/${t.id}`}
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
                  <TableCell className="text-right text-muted-foreground">
                    {formatDate(t.updatedAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      ) : (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
            <p className="text-sm text-muted-foreground">
              Vous n'avez aucun ticket pour le moment.
            </p>
            <NewTicketDialog onCreated={(t) => navigate(`/tickets/${t.id}`)} />
          </CardContent>
        </Card>
      )}
    </section>
  )
}
