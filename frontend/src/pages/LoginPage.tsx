import { useEffect } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { config } from '@/lib/config'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Separator } from '@/components/ui/separator'
import { useAuth } from '@/auth/context'

interface LocationState {
  from?: string
}

export function LoginPage() {
  const { user, loginAs, loginWithCognito } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as LocationState | null)?.from

  // Once authenticated, go to the deep link or the role home.
  useEffect(() => {
    if (!user) return
    if (from) {
      navigate(from, { replace: true })
      return
    }
    navigate(user.role === 'admin' ? '/admin/tickets' : '/tickets', { replace: true })
  }, [user, from, navigate])

  return (
    <main className="flex min-h-svh items-center justify-center bg-background p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>SmartCampus AI</CardTitle>
          <CardDescription>Connectez-vous pour accéder au portail.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {config.useMocks ? (
            <div className="space-y-2">
              <p className="text-sm text-muted-foreground">Mode démo — choisissez un rôle :</p>
              <Button className="w-full" onClick={() => loginAs('student')}>
                Entrer en tant qu'étudiant
              </Button>
              <Button className="w-full" variant="outline" onClick={() => loginAs('admin')}>
                Entrer en tant qu'administrateur
              </Button>
            </div>
          ) : (
            <Button className="w-full" onClick={() => void loginWithCognito()}>
              Se connecter
            </Button>
          )}

          {config.enableEntraFederation && (
            <>
              <div className="flex items-center gap-2">
                <Separator className="flex-1" />
                <span className="text-xs text-muted-foreground">ou</span>
                <Separator className="flex-1" />
              </div>
              {/* US06-AC1 — SSO Microsoft Entra ID, only shown when enabled. */}
              <Button
                className="w-full"
                variant="outline"
                onClick={() => void loginWithCognito(config.cognito.entraIdpName || undefined)}
              >
                Se connecter avec Microsoft
              </Button>
            </>
          )}
        </CardContent>
      </Card>
    </main>
  )
}
