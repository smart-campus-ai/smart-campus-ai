import { useState } from 'react'
import type { ReactElement } from 'react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import type { Ticket } from '@/domain/models'
import { TicketForm } from './TicketForm'

interface NewTicketDialogProps {
  /** Custom trigger; defaults to a primary "Nouveau ticket" button. */
  trigger?: ReactElement
  /** US10-AC2 — prefill coming from the chat escalation. */
  prefill?: { title?: string; description?: string }
  /** Controlled open state (used by the /tickets/new deep link). */
  open?: boolean
  onOpenChange?: (open: boolean) => void
  /** Called with the created ticket after the dialog closes. */
  onCreated?: (ticket: Ticket) => void
}

const FORM_ID = 'new-ticket-form'

export function NewTicketDialog({
  trigger,
  prefill,
  open,
  onOpenChange,
  onCreated,
}: NewTicketDialogProps) {
  const [internalOpen, setInternalOpen] = useState(false)
  const [pending, setPending] = useState(false)

  const isOpen = open ?? internalOpen
  const setOpen = onOpenChange ?? setInternalOpen

  return (
    <Dialog open={isOpen} onOpenChange={setOpen}>
      <DialogTrigger render={trigger ?? <Button>Nouveau ticket</Button>} />
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Nouveau ticket</DialogTitle>
          <DialogDescription>Signalez un besoin ou un incident sur le campus.</DialogDescription>
        </DialogHeader>

        <TicketForm
          formId={FORM_ID}
          prefill={prefill}
          hideSubmit
          onPendingChange={setPending}
          onCreated={(ticket) => {
            setOpen(false)
            onCreated?.(ticket)
          }}
        />

        <DialogFooter>
          <DialogClose render={<Button variant="outline">Annuler</Button>} />
          <Button type="submit" form={FORM_ID} disabled={pending}>
            {pending ? 'Création…' : 'Créer le ticket'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
