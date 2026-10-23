import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, FileText, History, MessageSquare } from 'lucide-react'
import { ApiError } from '@/domain/api'
import { Skeleton } from '@/components/ui/skeleton'
import { StatusBadge, PriorityBadge, formatDate } from '@/components/common/badges'
import { useAuth } from '@/auth/context'
import { useTicket } from '@/hooks/queries'
import { AdminTicketPanel } from './AdminTicketPanel'

export function TicketDetailPage() {
  const { ticketId } = useParams<{ ticketId: string }>()
  const { user } = useAuth()
  const { data: ticket, isLoading, error } = useTicket(ticketId)
  const isAdmin = user?.role === 'admin'
  const backTo = isAdmin ? '/admin/tickets' : '/tickets'

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-2/3" />
        <Skeleton className="h-40 w-full rounded-2xl" />
      </div>
    )
  }

  // US03-AC5 — a ticket owned by someone else is reported as 404 (BOLA).
  if (error) {
    const notFound = error instanceof ApiError && error.isNotFound
    return (
      <div
        role="alert"
        className="mx-auto max-w-md space-y-3 rounded-2xl bg-card p-8 text-center shadow-card ring-1 ring-foreground/5"
      >
        <h1 className="font-heading text-xl font-semibold">
          {notFound ? 'Ticket introuvable' : 'Erreur'}
        </h1>
        <p className="text-sm text-muted-foreground">
          {notFound
            ? "Ce ticket n'existe pas ou ne vous appartient pas."
            : 'Une erreur est survenue lors du chargement du ticket.'}
        </p>
        <Link
          to={backTo}
          className="inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-4 hover:underline"
        >
          <ArrowLeft className="size-4" />
          Retour aux tickets
        </Link>
      </div>
    )
  }

  if (!ticket) return null

  return (
    <article className="space-y-6">
      <Link
        to={backTo}
        className="inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
      >
        <ArrowLeft className="size-4" />
        Retour aux tickets
      </Link>

      <header className="rounded-2xl bg-card p-6 shadow-card ring-1 ring-foreground/5">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="font-heading text-xl font-semibold">{ticket.title}</h1>
          <StatusBadge status={ticket.status} />
          <PriorityBadge priority={ticket.priority} />
        </div>
        <p className="mt-2 text-sm text-muted-foreground">
          Réf. <span className="font-mono text-xs">{ticket.id}</span> · créé le{' '}
          {formatDate(ticket.createdAt)} · mis à jour le {formatDate(ticket.updatedAt)}
        </p>
      </header>

      <section className="rounded-2xl bg-card p-6 shadow-card ring-1 ring-foreground/5">
        <h2 className="mb-3 flex items-center gap-2 font-heading text-base font-medium">
          <FileText className="size-4 text-muted-foreground" />
          Description
        </h2>
        <p className="whitespace-pre-wrap text-sm leading-relaxed">{ticket.description}</p>
      </section>

      <section
        className="rounded-2xl bg-card p-6 shadow-card ring-1 ring-foreground/5"
        aria-label="Historique des commentaires"
      >
        <h2 className="mb-4 flex items-center gap-2 font-heading text-base font-medium">
          <MessageSquare className="size-4 text-muted-foreground" />
          Commentaires
        </h2>
        {ticket.notes.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucun commentaire.</p>
        ) : (
          <ul className="space-y-3">
            {ticket.notes.map((note) => (
              <li
                key={note.id}
                className="rounded-xl border border-border bg-background/50 p-4 text-sm"
              >
                <p className="whitespace-pre-wrap">{note.body}</p>
                <p className="mt-2 text-xs text-muted-foreground">
                  {formatDate(note.createdAt)}
                  {note.audience === 'internal' && (
                    <span className="ml-1.5 rounded bg-muted px-1.5 py-0.5 font-medium">
                      interne
                    </span>
                  )}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* US01-AC3 — audit trail, admins only. */}
      {isAdmin && ticket.history && ticket.history.length > 0 && (
        <section
          className="rounded-2xl bg-card p-6 shadow-card ring-1 ring-foreground/5"
          aria-label="Historique d'audit"
        >
          <h2 className="mb-4 flex items-center gap-2 font-heading text-base font-medium">
            <History className="size-4 text-muted-foreground" />
            Historique d'audit
          </h2>
          <ul className="space-y-2.5 text-sm">
            {ticket.history.map((e, i) => (
              <li key={`${e.at}-${i}`} className="flex flex-wrap gap-x-2 text-muted-foreground">
                <span className="font-mono text-xs">{formatDate(e.at)}</span>
                <span className="font-medium text-foreground">{e.field}</span>
                <span>
                  {e.oldValue ?? '∅'} → {e.newValue ?? '∅'}
                </span>
                <span className="text-xs">(par {e.actorSub})</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* US01 — admin management panel. */}
      {isAdmin && <AdminTicketPanel ticket={ticket} />}
    </article>
  )
}
