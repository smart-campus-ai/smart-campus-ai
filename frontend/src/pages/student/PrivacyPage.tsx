import { useState } from 'react'
import { toast } from 'sonner'
import { ShieldCheck, Trash2 } from 'lucide-react'
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
import { useDeleteChatHistory } from '@/hooks/queries'

export function PrivacyPage() {
  const deleteHistory = useDeleteChatHistory()
  const [open, setOpen] = useState(false)

  const confirmDelete = () => {
    deleteHistory.mutate(undefined, {
      onSuccess: () => {
        // US08-AC2 — clear the locally cached transcript as well.
        localStorage.removeItem('sc.chat.messages')
        localStorage.removeItem('sc.chat.sessionId')
        toast.success('Votre historique de conversation a été supprimé.')
        setOpen(false)
      },
      onError: () => toast.error('La suppression a échoué.'),
    })
  }

  return (
    <section className="mx-auto max-w-2xl space-y-6">
      <div className="flex items-center gap-3">
        <span className="flex size-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <ShieldCheck className="size-5" />
        </span>
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">
            Confidentialité
          </h1>
          <p className="text-sm text-muted-foreground">
            Gérez vos données personnelles conformément au RGPD.
          </p>
        </div>
      </div>

      <div className="space-y-4 rounded-2xl bg-card p-6 shadow-card ring-1 ring-foreground/5">
        <div className="space-y-1">
          <h2 className="font-heading text-base font-medium">Historique de conversation</h2>
          <p className="text-sm text-muted-foreground">
            Vous pouvez supprimer à tout moment l'intégralité de votre historique d'échanges avec
            l'assistant. Cette action est irréversible et ne concerne que vos propres sessions.
          </p>
        </div>

        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger
            render={
              <Button variant="destructive" className="gap-2">
                <Trash2 className="size-4" />
                Supprimer mon historique de chat
              </Button>
            }
          />
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Supprimer l'historique ?</DialogTitle>
              <DialogDescription>
                Toutes vos sessions de conversation seront définitivement supprimées.
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <DialogClose render={<Button variant="outline">Annuler</Button>} />
              <Button
                variant="destructive"
                onClick={confirmDelete}
                disabled={deleteHistory.isPending}
              >
                {deleteHistory.isPending ? 'Suppression…' : 'Confirmer la suppression'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </section>
  )
}
