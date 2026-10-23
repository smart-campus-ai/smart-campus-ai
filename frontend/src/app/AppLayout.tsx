import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { cn } from 'cn'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/auth/context'

interface NavItem {
  to: string
  label: string
}

const STUDENT_NAV: NavItem[] = [
  { to: '/tickets', label: 'Mes tickets' },
  { to: '/chat', label: 'Assistant' },
  { to: '/privacy', label: 'Confidentialité' },
]

const ADMIN_NAV: NavItem[] = [
  { to: '/admin/tickets', label: 'Tickets' },
  { to: '/admin/kpi', label: 'KPI' },
]

export function AppLayout() {
  const { user, logout } = useAuth()
  const location = useLocation()
  const nav = user?.role === 'admin' ? ADMIN_NAV : STUDENT_NAV
  // The chat uses the whole width and height; other pages stay comfortably centered.
  const fullBleed = location.pathname === '/chat'

  return (
    <div className="flex min-h-svh flex-col bg-background text-foreground">
      <header className="border-b">
        <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-4 px-4 py-3">
          <Link to={user?.role === 'admin' ? '/admin/tickets' : '/tickets'} className="font-semibold">
            SmartCampus AI
          </Link>
          <nav aria-label="Navigation principale" className="flex items-center gap-1">
            {nav.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/tickets'}
                className={({ isActive }) =>
                  cn(
                    'rounded-md px-3 py-1.5 text-sm transition-colors hover:bg-muted',
                    isActive && 'bg-muted font-medium',
                  )
                }
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex items-center gap-3">
            {user && (
              <span className="hidden text-sm text-muted-foreground sm:inline">
                {user.email} · {user.role}
              </span>
            )}
            <Button variant="outline" size="sm" onClick={logout}>
              Se déconnecter
            </Button>
          </div>
        </div>
      </header>
      <main className="flex min-h-0 w-full flex-1 flex-col">
        <div
          className={cn(
            'flex min-h-0 w-full flex-1 flex-col',
            fullBleed ? '' : 'mx-auto max-w-5xl px-4 py-6',
          )}
        >
          <Outlet />
        </div>
      </main>
    </div>
  )
}
