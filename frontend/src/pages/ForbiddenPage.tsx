import { useNavigate } from 'react-router-dom'
import { ShieldAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'

export function ForbiddenPage() {
  const navigate = useNavigate()
  return (
    <div className="flex min-h-svh flex-col items-center justify-center gap-5 bg-background p-6 text-center">
      <span className="flex size-16 items-center justify-center rounded-2xl bg-destructive/10 text-destructive">
        <ShieldAlert className="size-8" />
      </span>
      <div className="space-y-1.5">
        <h1 className="font-heading text-2xl font-semibold">Accès refusé</h1>
        <p className="max-w-sm text-muted-foreground">
          Vous n'avez pas les droits nécessaires pour accéder à cette page.
        </p>
      </div>
      <Button onClick={() => navigate('/')}>Retour à l'accueil</Button>
    </div>
  )
}
