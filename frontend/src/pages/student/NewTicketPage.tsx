import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { NewTicketDialog } from './NewTicketDialog'

/** US10-AC2 — prefill payload passed via router state from the chat escalation. */
interface PrefillState {
  prefill?: { title?: string; description?: string }
}

/**
 * Route host for /tickets/new. The creation form lives in a dialog; this route
 * opens it (e.g. from the chat escalation deep link) and returns to the ticket
 * list when it closes.
 */
export function NewTicketPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const prefill = (location.state as PrefillState | null)?.prefill
  const [open, setOpen] = useState(true)

  const close = () => {
    setOpen(false)
    navigate('/tickets', { replace: true })
  }

  return (
    <NewTicketDialog
      open={open}
      onOpenChange={(next) => {
        if (!next) close()
      }}
      prefill={prefill}
      trigger={<span className="sr-only" aria-hidden />}
      onCreated={(ticket) => navigate(`/tickets/${ticket.id}`)}
    />
  )
}
