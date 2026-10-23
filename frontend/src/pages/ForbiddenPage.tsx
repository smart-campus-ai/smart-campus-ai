import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'

export function ForbiddenPage() {
  const navigate = useNavigate()
  return (
    <div className="mx-auto flex min-h-svh max-w-md flex-col items-center justify-center gap-4 p-6 text-center">
      <h1 className="text-2xl font-semibold">Accès refusé</h1>
      <p className="text-muted-foreground">
        Vous n'avez pas les droits nécessaires pour accéder à cette page.
      </p>
      <Button onClick={() => navigate('/')}>Retour à l'accueil</Button>
    </div>
  )
}
