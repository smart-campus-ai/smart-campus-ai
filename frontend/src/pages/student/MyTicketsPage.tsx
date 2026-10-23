import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { CheckCircle2, Clock, Inbox, Ticket as TicketIcon } from 'lucide-react'
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
import { StatCard } from '@/components/common/StatCard'
import { FilterTags } from '@/components/common/FilterTags'
import { TICKET_STATUSES } from '@/domain/models'
import type { TicketListParams, TicketStatus } from '@/domain/models'
import { useTickets } from '@/hooks/queries'
import { NewTicketDialog } from './NewTicketDialog'

const STATUS_OPTIONS: { value: TicketStatus | ''; label: string }[] = [
  { value: '', label: 'Tous' },
  ...TICKET_STATUSES.map((s) => ({ value: s, label: s })),
]

const ORDER_OPTIONS: { value: 'desc' | 'asc'; label: string }[] = [
  { value: 'desc', label: 'Plus récents' },
  { value: 'asc', label: 'Plus anciens' },
]

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

  // Lightweight client-side rollup for the overview cards.
  const stats = useMemo(() => {
    const all = data?.items ?? []
    const open = all.filter((t) => t.status === 'Ouvert' || t.status === 'En cours').length
    const waiting = all.filter((t) => t.status === 'En attente étudiant').length
    const done = all.filter((t) => t.status === 'Résolu' || t.status === 'Fermé').length
    return { total: all.length, open, waiting, done }
  }, [data])

  return (
    <section className="animate-fade-in space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">Mes tickets</h1>
          <p className="text-sm text-muted-foreground">
            Suivez l'avancement de vos demandes de support.
          </p>
        </div>
        <NewTicketDialog onCreated={(t) => navigate(`/tickets/${t.id}`)} />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Total" value={stats.total} icon={TicketIcon} tone="primary" index={0} />
        <StatCard label="En cours" value={stats.open} icon={Clock} tone="warning" index={1} />
        <StatCard label="En attente de vous" value={stats.waiting} icon={Inbox} tone="neutral" index={2} />
        <StatCard label="Résolus" value={stats.done} icon={CheckCircle2} tone="success" index={3} />
      </div>

      <div className="flex flex-wrap items-start gap-x-8 gap-y-4">
        <FilterTags label="Statut" options={STATUS_OPTIONS} value={status} onChange={setStatus} />
        <FilterTags
          label="Tri"
          options={ORDER_OPTIONS}
          value={order}
          onChange={(v) => setOrder((v || 'desc') as 'asc' | 'desc')}
        />
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
        <div className="overflow-hidden rounded-2xl bg-card shadow-card ring-1 ring-foreground/5">
          <Table className="text-base">
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="h-14 px-6 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Titre
                </TableHead>
                <TableHead className="h-14 px-6 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Statut
                </TableHead>
                <TableHead className="h-14 px-6 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Priorité
                </TableHead>
                <TableHead className="h-14 px-6 text-right text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Dernière mise à jour
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((t, i) => (
                <TableRow
                  key={t.id}
                  className="animate-fade-up cursor-pointer transition-colors"
                  style={{ animationDelay: `${Math.min(i, 12) * 45}ms` }}
                  onClick={() => navigate(`/tickets/${t.id}`)}
                >
                  <TableCell className="px-6 py-5">
                    <Link
                      to={`/tickets/${t.id}`}
                      className="inline-block text-base font-semibold underline-offset-4 transition-colors duration-200 hover:text-primary hover:underline"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {t.title}
                    </Link>
                  </TableCell>
                  <TableCell className="px-6 py-5">
                    <StatusBadge status={t.status} />
                  </TableCell>
                  <TableCell className="px-6 py-5">
                    <PriorityBadge priority={t.priority} />
                  </TableCell>
                  <TableCell className="px-6 py-5 text-right text-sm text-muted-foreground">
                    {formatDate(t.updatedAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-4 rounded-2xl bg-card py-16 text-center shadow-card ring-1 ring-foreground/5">
          <span className="flex size-14 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <TicketIcon className="size-7" />
          </span>
          <div className="space-y-1">
            <p className="font-medium">Aucun ticket pour le moment</p>
            <p className="text-sm text-muted-foreground">
              Créez votre premier ticket pour signaler un besoin ou un incident.
            </p>
          </div>
          <NewTicketDialog onCreated={(t) => navigate(`/tickets/${t.id}`)} />
        </div>
      )}
    </section>
  )
}
