import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import type { Role } from '@/domain/models'
import { useAuth } from '@/auth/context'

interface ProtectedRouteProps {
  children: ReactNode
  /** Restrict to a specific role; omit to allow any authenticated user. */
  role?: Role
}

export function ProtectedRoute({ children, role }: ProtectedRouteProps) {
  const { user, isLoading } = useAuth()
  const location = useLocation()

  if (isLoading) return null

  if (!user) {
    // Preserve the target so we can return after login (US09 deep links).
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  }

  if (role && user.role !== role) {
    return <Navigate to="/forbidden" replace />
  }

  return <>{children}</>
}
