import { useEffect } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Bot, GraduationCap, ShieldCheck, Sparkles, Ticket } from 'lucide-react'
import { config } from '@/lib/config'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/auth/context'

interface LocationState {
  from?: string
}

const HIGHLIGHTS = [
  { icon: Ticket, title: 'Tickets', text: 'Déclarez et suivez vos incidents en temps réel.' },
  { icon: Bot, title: 'Assistant IA', text: 'Des réponses issues de la base de connaissances.' },
  { icon: ShieldCheck, title: 'RGPD', text: 'Vos données maîtrisées, suppression en un clic.' },
]

export function LoginPage() {
  const { user, loginAs, loginWithCognito } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as LocationState | null)?.from

  // Once authenticated, go to the deep link or the role home.
  useEffect(() => {
    if (!user) return

    const home = user.role === 'admin' ? '/admin/tickets' : '/tickets'
    // Only follow `from` when it belongs to the current role's area; otherwise
    // a deep link captured under a previous account (e.g. a student page) would
    // bounce an admin straight to /forbidden after switching accounts.
    const isAdminPath = from?.startsWith('/admin')
    const compatible = from && from !== '/login' && isAdminPath === (user.role === 'admin')

    navigate(compatible ? from : home, { replace: true })
  }, [user, from, navigate])

  return (
    <main className="flex min-h-svh w-full">
      {/* Hero panel */}
      <section className="bg-gradient-hero relative hidden w-1/2 flex-col justify-between overflow-hidden p-12 text-white lg:flex">
        <div className="flex items-center gap-3">
          <span className="bg-gradient-brand flex size-11 items-center justify-center rounded-2xl text-base font-bold shadow-lg">
            SC
          </span>
          <div className="leading-tight">
            <p className="font-heading text-lg font-semibold">SmartCampus AI</p>
            <p className="text-xs tracking-wide text-white/60">Capgemini × ESIEA</p>
          </div>
        </div>

        <div className="max-w-md space-y-6">
          <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-medium backdrop-blur">
            <Sparkles className="size-3.5" />
            Plateforme de gestion des incidents du campus
          </span>
          <h1 className="font-heading text-4xl font-semibold leading-tight">
            Le support du campus,
            <br />
            simple et intelligent.
          </h1>
          <p className="text-white/70">
            Déclarez un incident, discutez avec l'assistant, suivez la résolution. Les équipes
            gèrent le cycle de vie et pilotent les KPI.
          </p>
          <ul className="space-y-3 pt-2">
            {HIGHLIGHTS.map(({ icon: Icon, title, text }) => (
              <li key={title} className="flex items-start gap-3">
                <span className="mt-0.5 flex size-9 items-center justify-center rounded-lg bg-white/10 backdrop-blur">
                  <Icon className="size-[18px]" />
                </span>
                <div>
                  <p className="text-sm font-medium">{title}</p>
                  <p className="text-sm text-white/60">{text}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <p className="text-xs text-white/40">© {new Date().getFullYear()} ESIEA — Atelier Cloud</p>
      </section>

      {/* Form panel */}
      <section className="flex w-full flex-col items-center justify-center bg-background px-6 py-12 lg:w-1/2">
        <div className="w-full max-w-sm space-y-8">
          <div className="space-y-2 text-center lg:text-left">
            <span className="bg-gradient-brand inline-flex size-12 items-center justify-center rounded-2xl text-lg font-bold text-white shadow-md lg:hidden">
              SC
            </span>
            <h2 className="font-heading text-2xl font-semibold">Bienvenue</h2>
            <p className="text-sm text-muted-foreground">
              Connectez-vous pour accéder au portail SmartCampus AI.
            </p>
          </div>

          <div className="space-y-4 rounded-2xl bg-card p-6 shadow-card ring-1 ring-foreground/5">
            {config.useMocks ? (
              <div className="space-y-3">
                <p className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
                  <Sparkles className="size-3.5 text-primary" />
                  Mode démo — choisissez un rôle
                </p>
                <Button className="h-11 w-full gap-2" onClick={() => loginAs('student')}>
                  <GraduationCap className="size-4" />
                  Entrer en tant qu'étudiant
                </Button>
                <Button
                  className="h-11 w-full gap-2"
                  variant="outline"
                  onClick={() => loginAs('admin')}
                >
                  <ShieldCheck className="size-4" />
                  Entrer en tant qu'administrateur
                </Button>
              </div>
            ) : (
              <Button className="h-11 w-full" onClick={() => void loginWithCognito()}>
                Se connecter
              </Button>
            )}

            {config.enableEntraFederation && (
              <>
                <div className="flex items-center gap-3">
                  <span className="h-px flex-1 bg-border" />
                  <span className="text-xs text-muted-foreground">ou</span>
                  <span className="h-px flex-1 bg-border" />
                </div>
                {/* US06-AC1 — SSO Microsoft Entra ID, only shown when enabled. */}
                <Button
                  className="h-11 w-full"
                  variant="outline"
                  onClick={() => void loginWithCognito(config.cognito.entraIdpName || undefined)}
                >
                  Se connecter avec Microsoft
                </Button>
              </>
            )}
          </div>

          <p className="text-center text-xs text-muted-foreground">
            En vous connectant, vous acceptez la politique de confidentialité du campus.
          </p>
        </div>
      </section>
    </main>
  )
}
