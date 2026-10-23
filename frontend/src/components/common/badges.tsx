import { cn } from 'cn'
import type { TicketPriority, TicketStatus } from '@/domain/models'

/**
 * Status / priority chips. Colors are semantic (via dedicated classes rather
 * than the generic Badge variants) so the five statuses stay distinguishable
 * at a glance on the dashboard.
 */

const CHIP_BASE =
  'inline-flex h-6 w-fit items-center gap-1.5 rounded-full px-2.5 text-xs font-medium whitespace-nowrap'

const STATUS_STYLE: Record<TicketStatus, string> = {
  Ouvert: 'bg-primary/10 text-primary',
  'En cours': 'bg-warning/15 text-[color-mix(in_oklch,var(--warning),black_25%)]',
  'En attente étudiant': 'bg-muted text-muted-foreground',
  Résolu: 'bg-success/15 text-[color-mix(in_oklch,var(--success),black_15%)]',
  Fermé: 'bg-foreground/10 text-foreground/70',
}

const STATUS_DOT: Record<TicketStatus, string> = {
  Ouvert: 'bg-primary',
  'En cours': 'bg-warning',
  'En attente étudiant': 'bg-muted-foreground',
  Résolu: 'bg-success',
  Fermé: 'bg-foreground/50',
}

const PRIORITY_STYLE: Record<TicketPriority, string> = {
  basse: 'bg-muted text-muted-foreground',
  normale: 'bg-primary/10 text-primary',
  haute: 'bg-warning/15 text-[color-mix(in_oklch,var(--warning),black_25%)]',
  critique: 'bg-destructive/10 text-destructive',
}

export function StatusBadge({ status }: { status: TicketStatus }) {
  return (
    <span className={cn(CHIP_BASE, STATUS_STYLE[status])}>
      <span className={cn('size-1.5 rounded-full', STATUS_DOT[status])} aria-hidden />
      {status}
    </span>
  )
}

export function PriorityBadge({ priority }: { priority: TicketPriority }) {
  return (
    <span className={cn(CHIP_BASE, PRIORITY_STYLE[priority])}>
      {priority.charAt(0).toUpperCase() + priority.slice(1)}
    </span>
  )
}

export function formatDate(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString('fr-FR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}
