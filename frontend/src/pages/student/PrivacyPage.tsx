import { useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
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
    <section className="mx-auto max-w-2xl space-y-4">
      <h1 className="text-xl font-semibold">Confidentialité (RGPD)</h1>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Historique de conversation</CardTitle>
          <CardDescription>
            Vous pouvez supprimer à tout moment l'intégralité de votre historique d'échanges avec
            l'assistant. Cette action est irréversible et ne concerne que vos propres sessions.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger
              render={<Button variant="destructive">Supprimer mon historique de chat</Button>}
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
        </CardContent>
      </Card>
    </section>
  )
}
