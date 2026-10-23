import { useState } from 'react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import {
  BarChart3,
  Bot,
  LayoutGrid,
  LogOut,
  Menu,
  ShieldCheck,
  Ticket,
  X,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { cn } from 'cn'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/auth/context'

interface NavItem {
  to: string
  label: string
  icon: LucideIcon
  end?: boolean
}

const STUDENT_NAV: NavItem[] = [
  { to: '/tickets', label: 'Mes tickets', icon: Ticket, end: true },
  { to: '/chat', label: 'Assistant', icon: Bot },
  { to: '/privacy', label: 'Confidentialité', icon: ShieldCheck },
]

const ADMIN_NAV: NavItem[] = [
  { to: '/admin/tickets', label: 'Tickets', icon: LayoutGrid },
  { to: '/admin/kpi', label: 'KPI', icon: BarChart3 },
]

function initialsOf(email: string | undefined): string {
  if (!email) return '?'
  const name = email.split('@')[0] ?? email
  const parts = name.split(/[.\-_]/).filter(Boolean)
  const letters = (parts.length >= 2 ? parts[0][0] + parts[1][0] : name.slice(0, 2)) || '?'
  return letters.toUpperCase()
}

function BrandMark() {
  return (
    <div className="group flex items-center gap-2.5">
      <span className="bg-gradient-brand animate-gradient fx-swing animate-heartbeat flex size-9 items-center justify-center rounded-xl text-sm font-bold text-white shadow-sm">
        SC
      </span>
      <div className="leading-tight">
        <span className="font-heading block text-sm font-semibold text-white">SmartCampus</span>
        <span className="text-[11px] font-medium tracking-wide text-sidebar-muted">
          AI · ESIEA
        </span>
      </div>
    </div>
  )
}

function SidebarNav({ nav, onNavigate }: { nav: NavItem[]; onNavigate?: () => void }) {
  return (
    <nav aria-label="Navigation principale" className="flex flex-col gap-1 px-3">
      {nav.map((item, i) => {
        const Icon = item.icon
        return (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            onClick={onNavigate}
            style={{ animationDelay: `${i * 80}ms` }}
            className={({ isActive }) =>
              cn(
                'group fx-wobble animate-fade-left relative flex items-center gap-3 overflow-hidden rounded-lg px-3 py-2.5 text-sm font-medium transition-all duration-200',
                'text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground hover:translate-x-2 hover:scale-105',
                isActive && 'bg-sidebar-accent text-sidebar-accent-foreground animate-rainbow-glow',
              )
            }
          >
            {({ isActive }) => (
              <>
                <span
                  aria-hidden
                  className={cn(
                    'absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-sidebar-primary transition-all duration-300',
                    isActive ? 'scale-y-100 opacity-100' : 'scale-y-0 opacity-0',
                  )}
                />
                <Icon
                  className={cn(
                    'fx-spin-on-hover size-[18px] shrink-0 transition-transform duration-200 group-hover:scale-125',
                    isActive && 'text-sidebar-primary',
                  )}
                />
                <span>{item.label}</span>
              </>
            )}
          </NavLink>
        )
      })}
    </nav>
  )
}

export function AppLayout() {
  const { user, logout } = useAuth()
  const location = useLocation()
  const [mobileOpen, setMobileOpen] = useState(false)
  const isAdmin = user?.role === 'admin'
  const nav = isAdmin ? ADMIN_NAV : STUDENT_NAV
  // The chat uses the whole width and height; other pages get comfortable padding.
  const fullBleed = location.pathname === '/chat'

  const sidebarInner = (
    <div className="flex h-full flex-col gap-6 py-5">
      <div className="px-5">
        <Link to={isAdmin ? '/admin/tickets' : '/tickets'} onClick={() => setMobileOpen(false)}>
          <BrandMark />
        </Link>
      </div>

      <div className="flex-1 overflow-y-auto scroll-area">
        <p className="px-6 pb-2 text-[11px] font-semibold uppercase tracking-wider text-sidebar-muted">
          {isAdmin ? 'Administration' : 'Espace étudiant'}
        </p>
        <SidebarNav nav={nav} onNavigate={() => setMobileOpen(false)} />
      </div>

      <div className="mx-3 rounded-xl bg-sidebar-accent p-3">
        <div className="flex items-center gap-3">
          <span className="bg-gradient-brand flex size-9 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white">
            {initialsOf(user?.email)}
          </span>
          <div className="min-w-0 flex-1 leading-tight">
            <p className="truncate text-sm font-medium text-white">{user?.email}</p>
            <p className="text-[11px] capitalize text-sidebar-muted">{user?.role}</p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={logout}
          className="mt-2.5 w-full justify-start gap-2 text-sidebar-foreground hover:bg-white/10 hover:text-white"
        >
          <LogOut className="size-4" />
          Se déconnecter
        </Button>
      </div>
    </div>
  )

  return (
    <div className="flex h-svh w-full overflow-hidden bg-background text-foreground">
      {/* Desktop sidebar */}
      <aside className="hidden w-64 shrink-0 bg-sidebar lg:block">{sidebarInner}</aside>

      {/* Mobile drawer */}
      {mobileOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            type="button"
            aria-label="Fermer le menu"
            className="absolute inset-0 bg-black/50 backdrop-blur-sm"
            onClick={() => setMobileOpen(false)}
          />
          <div className="relative h-full w-64 bg-sidebar shadow-float">{sidebarInner}</div>
        </div>
      )}

      {/* Main column */}
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Floating menu button on mobile (no top header). */}
        <Button
          variant="default"
          size="icon"
          className="fixed left-4 top-4 z-40 shadow-float lg:hidden"
          aria-label="Ouvrir le menu"
          onClick={() => setMobileOpen(true)}
        >
          <Menu className="size-5" />
        </Button>

        <main
          className={cn(
            'min-h-0 flex-1 overflow-y-auto scroll-area',
            fullBleed ? 'flex flex-col' : '',
          )}
        >
          {fullBleed ? (
            <Outlet />
          ) : (
            <div className="w-full px-4 py-6 sm:px-8 sm:py-8">
              <Outlet />
            </div>
          )}
        </main>
      </div>

      {/* Close button for mobile drawer, floated for a11y when open */}
      {mobileOpen && (
        <Button
          variant="ghost"
          size="icon"
          aria-label="Fermer le menu"
          onClick={() => setMobileOpen(false)}
          className="fixed right-4 top-4 z-[60] text-white lg:hidden"
        >
          <X className="size-5" />
        </Button>
      )}
    </div>
  )
}
