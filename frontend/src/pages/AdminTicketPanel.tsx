import { useState } from 'react'
import { toast } from 'sonner'
import { ApiError } from '@/domain/api'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { RequiredMark } from '@/components/common/RequiredMark'
import {
  CLOSING_STATUSES,
  TICKET_PRIORITIES,
  TICKET_STATUSES,
} from '@/domain/models'
import type {
  NoteAudience,
  TicketDetail,
  TicketPriority,
  TicketStatus,
  TicketUpdateInput,
} from '@/domain/models'
import { useUpdateTicket } from '@/hooks/queries'

export function AdminTicketPanel({ ticket }: { ticket: TicketDetail }) {
  const [status, setStatus] = useState<TicketStatus>(ticket.status)
  const [priority, setPriority] = useState<TicketPriority>(ticket.priority)
  const [assigneeSub, setAssigneeSub] = useState<string>(ticket.assigneeSub ?? '')
  const [noteBody, setNoteBody] = useState('')
  const [noteAudience, setNoteAudience] = useState<NoteAudience>('student')
  const [resolutionNote, setResolutionNote] = useState('')
  const [error, setError] = useState<string | null>(null)

  const mutation = useUpdateTicket(ticket.id)
  const requiresResolution = CLOSING_STATUSES.includes(status)

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)

    // US01-AC5 — block client-side too; the API also enforces 400.
    if (requiresResolution && !resolutionNote.trim()) {
      setError('Une note de résolution est obligatoire pour clôturer un ticket.')
      return
    }

    // The contract carries a single note object. When closing, the resolution
    // note is sent as a student-facing note; otherwise the free comment is used.
    const note = requiresResolution
      ? { body: `Résolution : ${resolutionNote.trim()}`, audience: 'student' as NoteAudience }
      : noteBody.trim()
        ? { body: noteBody.trim(), audience: noteAudience }
        : undefined

    const input: TicketUpdateInput = {
      status: status !== ticket.status ? status : undefined,
      priority: priority !== ticket.priority ? priority : undefined,
      assigneeSub: assigneeSub.trim() !== (ticket.assigneeSub ?? '') ? assigneeSub.trim() : undefined,
      note,
    }

    mutation.mutate(input, {
      onSuccess: () => {
        toast.success('Ticket mis à jour.')
        setNoteBody('')
        setResolutionNote('')
      },
      onError: (err) => {
        if (err instanceof ApiError && err.isValidation) {
          setError(err.message)
        } else {
          setError('La mise à jour a échoué.')
        }
      },
    })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Gestion du ticket</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={onSubmit} aria-label="Gestion du ticket">
          <div className="grid gap-4 sm:grid-cols-3">
            <div className="space-y-1">
              <Label htmlFor="admin-status">Statut</Label>
              <select
                id="admin-status"
                className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm transition-all duration-200 outline-none hover:border-ring/60 focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/50"
                value={status}
                onChange={(e) => setStatus(e.target.value as TicketStatus)}
              >
                {TICKET_STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="admin-priority">Priorité</Label>
              <select
                id="admin-priority"
                className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm transition-all duration-200 outline-none hover:border-ring/60 focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/50"
                value={priority}
                onChange={(e) => setPriority(e.target.value as TicketPriority)}
              >
                {TICKET_PRIORITIES.map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="admin-assignee">Assigné à (sub)</Label>
              <Input
                id="admin-assignee"
                value={assigneeSub}
                onChange={(e) => setAssigneeSub(e.target.value)}
                placeholder="sub de l'opérateur"
              />
            </div>
          </div>

          {!requiresResolution && (
            <div className="grid gap-4 sm:grid-cols-[1fr_auto]">
              <div className="space-y-1">
                <Label htmlFor="admin-note">Commentaire</Label>
                <Textarea
                  id="admin-note"
                  value={noteBody}
                  onChange={(e) => setNoteBody(e.target.value)}
                  rows={2}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="admin-note-audience">Visibilité</Label>
                <select
                  id="admin-note-audience"
                  className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm transition-all duration-200 outline-none hover:border-ring/60 focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/50"
                  value={noteAudience}
                  onChange={(e) => setNoteAudience(e.target.value as NoteAudience)}
                >
                  <option value="student">Visible par l'étudiant</option>
                  <option value="internal">Interne</option>
                </select>
              </div>
            </div>
          )}

          {requiresResolution && (
            <div className="space-y-1">
              <Label htmlFor="admin-resolution">
                Note de résolution <RequiredMark />
              </Label>
              <Textarea
                id="admin-resolution"
                value={resolutionNote}
                onChange={(e) => setResolutionNote(e.target.value)}
                rows={2}
                aria-required="true"
                aria-invalid={Boolean(error) && !resolutionNote.trim()}
              />
            </div>
          )}

          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}

          <Button type="submit" disabled={mutation.isPending}>
            {mutation.isPending ? 'Enregistrement…' : 'Enregistrer'}
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
