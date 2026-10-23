import { useState } from 'react'
import { toast } from 'sonner'
import { ApiError } from '@/domain/api'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { RequiredMark } from '@/components/common/RequiredMark'
import type { TicketDetail } from '@/domain/models'
import { useReplyToTicket } from '@/hooks/queries'

/**
 * US03 — when a ticket is "En attente étudiant", the support team is waiting
 * for information from the student. This panel lets the owner reply; the reply
 * is added to the conversation and hands the ticket back to support.
 */
export function StudentReplyPanel({ ticket }: { ticket: TicketDetail }) {
  const [body, setBody] = useState('')
  const [error, setError] = useState<string | null>(null)
  const mutation = useReplyToTicket(ticket.id)

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    if (!body.trim()) {
      setError('Votre réponse ne peut pas être vide.')
      return
    }
    mutation.mutate(
      { body: body.trim() },
      {
        onSuccess: () => {
          toast.success('Votre réponse a été envoyée au support.')
          setBody('')
        },
        onError: (err) => {
          setError(
            err instanceof ApiError ? err.message : "L'envoi de votre réponse a échoué.",
          )
        },
      },
    )
  }

  return (
    <Card className="border-accent/40 bg-accent/5">
      <CardHeader>
        <CardTitle className="text-base">Une réponse de votre part est attendue</CardTitle>
        <CardDescription>
          Le support attend une information pour avancer sur votre ticket. Répondez ci-dessous ;
          votre message sera transmis et le ticket repassera « En cours ».
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form className="space-y-3" onSubmit={onSubmit} aria-label="Répondre au support">
          <div className="space-y-1.5">
            <Label htmlFor="student-reply">
              Votre réponse <RequiredMark />
            </Label>
            <Textarea
              id="student-reply"
              rows={3}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              required
              aria-required="true"
              aria-invalid={Boolean(error)}
              placeholder="Apportez l'information demandée…"
            />
          </div>
          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
          <Button type="submit" disabled={mutation.isPending}>
            {mutation.isPending ? 'Envoi…' : 'Envoyer ma réponse'}
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
