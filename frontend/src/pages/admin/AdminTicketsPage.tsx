import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle, CheckCircle2, Inbox, LayoutGrid } from 'lucide-react'
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

  const stats = useMemo(() => {
    const all = data?.items ?? []
    const open = all.filter((t) => t.status === 'Ouvert').length
    const critical = all.filter((t) => t.priority === 'critique').length
    const resolved = all.filter((t) => t.status === 'Résolu' || t.status === 'Fermé').length
    return { total: all.length, open, critical, resolved }
  }, [data])

  return (
    <section className="animate-fade-in space-y-8">
      <div>
        <h1 className="font-heading text-2xl font-semibold tracking-tight">Tickets</h1>
        <p className="text-sm text-muted-foreground">
          Gérez le cycle de vie des demandes du campus.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Total" value={stats.total} icon={LayoutGrid} tone="primary" index={0} />
        <StatCard label="Ouverts" value={stats.open} icon={Inbox} tone="warning" index={1} />
        <StatCard label="Critiques" value={stats.critical} icon={AlertTriangle} tone="destructive" index={2} />
        <StatCard label="Résolus" value={stats.resolved} icon={CheckCircle2} tone="success" index={3} />
      </div>

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
        <div className="overflow-hidden rounded-2xl bg-card shadow-card ring-1 ring-foreground/5">
          <Table className="text-base">
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="h-14 px-6 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Réf.
                </TableHead>
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
                  Créé le
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((t, i) => (
                <TableRow
                  key={t.id}
                  className="fx-wobble animate-bounce-in cursor-pointer transition-all duration-200 hover:scale-[1.01] hover:bg-primary/5"
                  style={{ animationDelay: `${Math.min(i, 12) * 45}ms` }}
                >
                  <TableCell className="px-6 py-5 font-mono text-sm text-muted-foreground">
                    {t.id.slice(0, 10)}…
                  </TableCell>
                  <TableCell className="px-6 py-5">
                    <Link
                      to={`/admin/tickets/${t.id}`}
                      className="inline-block text-base font-semibold underline-offset-4 transition-colors duration-200 hover:text-primary hover:underline"
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
                    {formatDate(t.createdAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-3 rounded-2xl bg-card py-16 text-center shadow-card ring-1 ring-foreground/5">
          <span className="flex size-14 items-center justify-center rounded-2xl bg-muted text-muted-foreground">
            <Inbox className="size-7" />
          </span>
          <p className="text-sm text-muted-foreground">Aucun ticket.</p>
        </div>
      )}
    </section>
  )
}
