import { useState } from 'react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { CheckCircle2, Clock, Inbox, Layers } from 'lucide-react'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Skeleton } from '@/components/ui/skeleton'
import { StatCard } from '@/components/common/StatCard'
import { FilterTags } from '@/components/common/FilterTags'
import { TICKET_CATEGORIES, TICKET_STATUSES } from '@/domain/models'
import type { KpiParams, TicketCategory, TicketStatus } from '@/domain/models'
import { useKpi } from '@/hooks/queries'

const STATUS_OPTIONS: { value: TicketStatus | ''; label: string }[] = [
  { value: '', label: 'Tous' },
  ...TICKET_STATUSES.map((s) => ({ value: s, label: s })),
]

const CATEGORY_OPTIONS: { value: TicketCategory | ''; label: string }[] = [
  { value: '', label: 'Toutes' },
  ...TICKET_CATEGORIES.map((c) => ({ value: c, label: c })),
]

const GRANULARITY_OPTIONS: { value: 'day' | 'week' | 'month'; label: string }[] = [
  { value: 'day', label: 'Jour' },
  { value: 'week', label: 'Semaine' },
  { value: 'month', label: 'Mois' },
]

function isoDate(offsetDays = 0): string {
  return new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10)
}

export function AdminKpiPage() {
  const [from, setFrom] = useState(() => isoDate(-30))
  const [to, setTo] = useState(() => isoDate(0))
  const [status, setStatus] = useState<'' | TicketStatus>('')
  const [category, setCategory] = useState<'' | TicketCategory>('')
  const [granularity, setGranularity] = useState<'day' | 'week' | 'month'>('day')
  const [showTable, setShowTable] = useState(false)

  const params: KpiParams = {
    from,
    to,
    status: status || undefined,
    category: category || undefined,
    granularity,
  }
  const { data, isLoading, isError } = useKpi(params)

  return (
    <section className="space-y-8">
      <div>
        <h1 className="font-heading text-2xl font-semibold tracking-tight">Tableau de bord KPI</h1>
        <p className="text-sm text-muted-foreground">
          Pilotez le volume et la performance de résolution des tickets.
        </p>
      </div>

      {/* US05-AC2 — filters. */}
      <div className="space-y-5 rounded-2xl bg-card p-5 shadow-card ring-1 ring-foreground/5">
        <div className="flex flex-wrap items-end gap-4">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="kpi-from" className="text-sm font-medium">
              Du
            </label>
            <input
              id="kpi-from"
              type="date"
              className="h-9 rounded-lg border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="kpi-to" className="text-sm font-medium">
              Au
            </label>
            <input
              id="kpi-to"
              type="date"
              className="h-9 rounded-lg border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
              value={to}
              onChange={(e) => setTo(e.target.value)}
            />
          </div>
        </div>
        <div className="flex flex-wrap items-start gap-x-8 gap-y-4">
          <FilterTags label="Statut" options={STATUS_OPTIONS} value={status} onChange={setStatus} />
          <FilterTags
            label="Catégorie"
            options={CATEGORY_OPTIONS}
            value={category}
            onChange={setCategory}
          />
          <FilterTags
            label="Granularité"
            options={GRANULARITY_OPTIONS}
            value={granularity}
            onChange={(v) => setGranularity((v || 'day') as 'day' | 'week' | 'month')}
          />
        </div>
      </div>

      {isError && (
        <p role="alert" className="text-sm text-destructive">
          Impossible de charger les KPI.
        </p>
      )}

      {isLoading ? (
        <Skeleton className="h-64 w-full rounded-2xl" />
      ) : data ? (
        <>
          {/* US05-AC1 — indicators. */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              label="Volume de tickets"
              value={data.summary.totalTickets}
              icon={Layers}
              tone="primary"
            />
            <StatCard
              label="Tickets ouverts"
              value={data.summary.openTickets}
              icon={Inbox}
              tone="warning"
            />
            <StatCard
              label="Tickets résolus"
              value={data.summary.resolvedTickets}
              icon={CheckCircle2}
              tone="success"
            />
            <StatCard
              label="Temps moyen de résolution"
              value={
                data.summary.averageResolutionSeconds === null
                  ? '—'
                  : `${Math.round(data.summary.averageResolutionSeconds / 3600)} h`
              }
              icon={Clock}
              tone="neutral"
            />
          </div>

          <div className="space-y-4 rounded-2xl bg-card p-5 shadow-card ring-1 ring-foreground/5">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="font-heading text-lg font-medium">Tendance</h2>
                <p className="text-xs text-muted-foreground">
                  Tickets créés et résolus sur la période.
                </p>
              </div>
              {/* US05-AC3 — accessible tabular alternative to the chart. */}
              <button
                type="button"
                className="rounded-lg border border-border px-3 py-1.5 text-sm font-medium transition-colors hover:bg-muted"
                onClick={() => setShowTable((v) => !v)}
                aria-pressed={showTable}
              >
                {showTable ? 'Afficher le graphique' : 'Afficher le tableau'}
              </button>
            </div>

            {showTable ? (
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Période</TableHead>
                    <TableHead>Créés</TableHead>
                    <TableHead>Résolus</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.trend.map((d) => (
                    <TableRow key={d.bucket}>
                      <TableCell>{d.bucket}</TableCell>
                      <TableCell>{d.created}</TableCell>
                      <TableCell>{d.resolved}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            ) : (
              <div
                className="h-72 w-full"
                role="img"
                aria-label="Graphique de tendance des tickets créés et résolus"
              >
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={data.trend} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
                    <defs>
                      <linearGradient id="fillCreated" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#36A9E1" stopOpacity={0.35} />
                        <stop offset="95%" stopColor="#36A9E1" stopOpacity={0} />
                      </linearGradient>
                      <linearGradient id="fillResolved" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#F59E00" stopOpacity={0.35} />
                        <stop offset="95%" stopColor="#F59E00" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
                    <XAxis
                      dataKey="bucket"
                      tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                      tickLine={false}
                      axisLine={false}
                    />
                    <YAxis
                      tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                      allowDecimals={false}
                      tickLine={false}
                      axisLine={false}
                    />
                    <Tooltip
                      contentStyle={{
                        borderRadius: 12,
                        border: '1px solid var(--border)',
                        background: 'var(--popover)',
                        color: 'var(--popover-foreground)',
                        boxShadow: 'var(--shadow-float)',
                      }}
                    />
                    <Area
                      type="monotone"
                      dataKey="created"
                      stroke="#36A9E1"
                      strokeWidth={2}
                      fill="url(#fillCreated)"
                      name="Créés"
                    />
                    <Area
                      type="monotone"
                      dataKey="resolved"
                      stroke="#F59E00"
                      strokeWidth={2}
                      fill="url(#fillResolved)"
                      name="Résolus"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>
        </>
      ) : null}
    </section>
  )
}
