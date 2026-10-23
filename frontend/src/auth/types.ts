import type { Role } from '@/domain/models'

export interface AuthUser {
  sub: string
  email: string
  role: Role
  /** Access token (JWT) forwarded as Bearer to the API. Empty in mock mode. */
  token: string
}

export interface AuthContextValue {
  user: AuthUser | null
  isLoading: boolean
  /** Mock mode: logs in directly as the given role. Real mode: ignored. */
  loginAs: (role: Role) => void
  /** Real mode: redirect to Cognito Hosted UI (optionally via the Entra IdP). */
  loginWithCognito: (idpName?: string) => Promise<void>
  logout: () => void
}

/** US06 — derive the role from the Cognito groups claim. */
export function roleFromGroups(groups: unknown): Role {
  if (Array.isArray(groups) && groups.includes('admin')) return 'admin'
  return 'student'
}
