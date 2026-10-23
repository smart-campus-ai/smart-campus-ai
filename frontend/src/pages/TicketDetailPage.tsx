import { useParams } from 'react-router-dom'
import { ApiError } from '@/domain/api'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import { StatusBadge, PriorityBadge, formatDate } from '@/components/common/badges'
import { useAuth } from '@/auth/context'
import { useTicket } from '@/hooks/queries'
import { AdminTicketPanel } from './AdminTicketPanel'

export function TicketDetailPage() {
  const { ticketId } = useParams<{ ticketId: string }>()
  const { user } = useAuth()
  const { data: ticket, isLoading, error } = useTicket(ticketId)

  if (isLoading) {
    return (
      <div className="space-y-3">
        <Skeleton className="h-8 w-2/3" />
        <Skeleton className="h-40 w-full" />
      </div>
    )
  }

  // US03-AC5 — a ticket owned by someone else is reported as 404 (BOLA).
  if (error) {
    const notFound = error instanceof ApiError && error.isNotFound
    return (
      <div role="alert" className="space-y-2">
        <h1 className="text-xl font-semibold">
          {notFound ? 'Ticket introuvable' : 'Erreur'}
        </h1>
        <p className="text-muted-foreground">
          {notFound
            ? "Ce ticket n'existe pas ou ne vous appartient pas."
            : 'Une erreur est survenue lors du chargement du ticket.'}
        </p>
      </div>
    )
  }

  if (!ticket) return null

  const isAdmin = user?.role === 'admin'

  return (
    <article className="space-y-6">
      <header className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-xl font-semibold">{ticket.title}</h1>
          <StatusBadge status={ticket.status} />
          <PriorityBadge priority={ticket.priority} />
        </div>
        <p className="text-sm text-muted-foreground">
          Réf. {ticket.id} · créé le {formatDate(ticket.createdAt)} · mis à jour le{' '}
          {formatDate(ticket.updatedAt)}
        </p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Description</CardTitle>
        </CardHeader>
        <CardContent className="whitespace-pre-wrap text-sm">{ticket.description}</CardContent>
      </Card>

      <section className="space-y-3" aria-label="Historique des commentaires">
        <h2 className="text-lg font-medium">Commentaires</h2>
        {ticket.notes.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucun commentaire.</p>
        ) : (
          <ul className="space-y-3">
            {ticket.notes.map((note) => (
              <li key={note.id} className="rounded-lg border p-3 text-sm">
                <p className="whitespace-pre-wrap">{note.body}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {formatDate(note.createdAt)}
                  {note.audience === 'internal' && ' · interne'}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* US01-AC3 — audit trail, admins only. */}
      {isAdmin && ticket.history && ticket.history.length > 0 && (
        <section className="space-y-3" aria-label="Historique d'audit">
          <Separator />
          <h2 className="text-lg font-medium">Historique d'audit</h2>
          <ul className="space-y-2 text-sm">
            {ticket.history.map((e, i) => (
              <li key={`${e.at}-${i}`} className="text-muted-foreground">
                <span className="font-mono text-xs">{formatDate(e.at)}</span> — {e.field}
                {' : '}
                {e.oldValue ?? '∅'} → {e.newValue ?? '∅'}{' '}
                <span className="text-xs">(par {e.actorSub})</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* US01 — admin management panel. */}
      {isAdmin && (
        <>
          <Separator />
          <AdminTicketPanel ticket={ticket} />
        </>
      )}
    </article>
  )
}
