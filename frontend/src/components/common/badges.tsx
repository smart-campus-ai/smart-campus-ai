import { Badge } from '@/components/ui/badge'
import type { TicketPriority, TicketStatus } from '@/domain/models'

type BadgeVariant = 'default' | 'secondary' | 'destructive' | 'outline'

const STATUS_VARIANT: Record<TicketStatus, BadgeVariant> = {
  Ouvert: 'default',
  'En cours': 'secondary',
  'En attente étudiant': 'outline',
  Résolu: 'secondary',
  Fermé: 'outline',
}

const PRIORITY_VARIANT: Record<TicketPriority, BadgeVariant> = {
  basse: 'outline',
  normale: 'secondary',
  haute: 'default',
  critique: 'destructive',
}

export function StatusBadge({ status }: { status: TicketStatus }) {
  return <Badge variant={STATUS_VARIANT[status]}>{status}</Badge>
}

export function PriorityBadge({ priority }: { priority: TicketPriority }) {
  return (
    <Badge variant={PRIORITY_VARIANT[priority]}>
      {priority.charAt(0).toUpperCase() + priority.slice(1)}
    </Badge>
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
