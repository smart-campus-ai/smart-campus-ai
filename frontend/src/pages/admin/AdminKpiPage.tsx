import { useState } from 'react'
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Skeleton } from '@/components/ui/skeleton'
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

function Kpi({ label, value }: { label: string; value: string | number }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{label}</CardDescription>
        <CardTitle className="text-2xl">{value}</CardTitle>
      </CardHeader>
      <CardContent />
    </Card>
  )
}

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
    <section className="space-y-6">
      <h1 className="text-2xl font-semibold tracking-tight">Tableau de bord KPI</h1>

      {/* US05-AC2 — filters. */}
      <div className="space-y-4">
        <div className="flex flex-wrap items-end gap-4">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="kpi-from" className="text-sm font-medium">Du</label>
            <input
              id="kpi-from"
              type="date"
              className="h-9 rounded-md border border-input bg-background px-2.5 text-sm"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="kpi-to" className="text-sm font-medium">Au</label>
            <input
              id="kpi-to"
              type="date"
              className="h-9 rounded-md border border-input bg-background px-2.5 text-sm"
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
        <p role="alert" className="text-sm text-destructive">Impossible de charger les KPI.</p>
      )}

      {isLoading ? (
        <Skeleton className="h-64 w-full" />
      ) : data ? (
        <>
          {/* US05-AC1 — indicators. */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Kpi label="Volume de tickets" value={data.summary.totalTickets} />
            <Kpi label="Tickets ouverts" value={data.summary.openTickets} />
            <Kpi label="Tickets résolus" value={data.summary.resolvedTickets} />
            <Kpi
              label="Temps moyen de résolution"
              value={
                data.summary.averageResolutionSeconds === null
                  ? '—'
                  : `${Math.round(data.summary.averageResolutionSeconds / 3600)} h`
              }
            />
          </div>

          <div className="flex items-center justify-between">
            <h2 className="text-lg font-medium">Tendance</h2>
            {/* US05-AC3 — accessible tabular alternative to the chart. */}
            <button
              type="button"
              className="text-sm underline underline-offset-4"
              onClick={() => setShowTable((v) => !v)}
              aria-pressed={showTable}
            >
              {showTable ? 'Afficher le graphique' : 'Afficher le tableau'}
            </button>
          </div>

          {showTable ? (
            <Table>
              <TableHeader>
                <TableRow>
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
            <div className="h-72 w-full" role="img" aria-label="Graphique de tendance des tickets créés et résolus">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={data.trend}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="bucket" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
                  <Tooltip />
                  <Line type="monotone" dataKey="created" stroke="#36A9E1" name="Créés" />
                  <Line type="monotone" dataKey="resolved" stroke="#F59E00" name="Résolus" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
        </>
      ) : null}
    </section>
  )
}
