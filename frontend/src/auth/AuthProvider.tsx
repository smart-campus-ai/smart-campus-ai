import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { config } from '@/lib/config'
import type { Role } from '@/domain/models'
import { AuthContext } from './context'
import type { AuthContextValue, AuthUser } from './types'
import { roleFromGroups } from './types'
import { challengeFromVerifier, decodeJwt, randomVerifier } from './pkce'

const STORAGE_KEY = 'sc.auth.user'
const VERIFIER_KEY = 'sc.auth.pkce_verifier'

const MOCK_USERS: Record<Role, AuthUser> = {
  student: { sub: 'student-001', email: 'alice@esiea.fr', role: 'student', token: '' },
  admin: { sub: 'admin-001', email: 'admin@esiea.fr', role: 'admin', token: '' },
}

function loadStoredUser(): AuthUser | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? (JSON.parse(raw) as AuthUser) : null
  } catch {
    return null
  }
}

function persistUser(user: AuthUser | null): void {
  if (user) localStorage.setItem(STORAGE_KEY, JSON.stringify(user))
  else localStorage.removeItem(STORAGE_KEY)
}

interface AuthProviderProps {
  children: ReactNode
  /** Called whenever the acting user changes, so the API layer can follow (mock identity). */
  onUserChange?: (user: AuthUser | null) => void
}

export function AuthProvider({ children, onUserChange }: AuthProviderProps) {
  const [user, setUser] = useState<AuthUser | null>(() => loadStoredUser())
  const [isLoading, setIsLoading] = useState<boolean>(!config.useMocks)

  const update = useCallback(
    (next: AuthUser | null) => {
      setUser(next)
      persistUser(next)
      onUserChange?.(next)
    },
    [onUserChange],
  )

  // Keep the API layer in sync with the initially restored user.
  useEffect(() => {
    onUserChange?.(user)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const loginAs = useCallback(
    (role: Role) => {
      update(MOCK_USERS[role])
    },
    [update],
  )

  const loginWithCognito = useCallback(async (idpName?: string) => {
    const verifier = randomVerifier()
    const challenge = await challengeFromVerifier(verifier)
    sessionStorage.setItem(VERIFIER_KEY, verifier)

    const params = new URLSearchParams({
      response_type: 'code',
      client_id: config.cognito.clientId,
      redirect_uri: config.cognito.redirectUri,
      scope: config.cognito.scope,
      code_challenge: challenge,
      code_challenge_method: 'S256',
    })
    // US06 — route directly to the Entra IdP when requested.
    if (idpName) params.set('identity_provider', idpName)

    window.location.assign(`${config.cognito.domain}/oauth2/authorize?${params.toString()}`)
  }, [])

  // Handle the OAuth redirect (?code=...) on load in real mode.
  useEffect(() => {
    if (config.useMocks) return
    const url = new URL(window.location.href)
    const code = url.searchParams.get('code')
    if (!code) {
      setIsLoading(false)
      return
    }
    const verifier = sessionStorage.getItem(VERIFIER_KEY)
    if (!verifier) {
      setIsLoading(false)
      return
    }

    const exchange = async () => {
      try {
        const body = new URLSearchParams({
          grant_type: 'authorization_code',
          client_id: config.cognito.clientId,
          code,
          redirect_uri: config.cognito.redirectUri,
          code_verifier: verifier,
        })
        const res = await fetch(`${config.cognito.domain}/oauth2/token`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body,
        })
        if (!res.ok) throw new Error('token exchange failed')
        const tokens = (await res.json()) as {
          access_token: string
          id_token: string
        }
        const claims = decodeJwt(tokens.id_token)
        const next: AuthUser = {
          sub: String(claims.sub ?? ''),
          email: String(claims.email ?? ''),
          role: roleFromGroups(claims['cognito:groups']),
          token: tokens.access_token,
        }
        update(next)
      } catch {
        // swallow — user stays logged out and lands back on the login screen
      } finally {
        sessionStorage.removeItem(VERIFIER_KEY)
        window.history.replaceState({}, '', url.pathname)
        setIsLoading(false)
      }
    }
    void exchange()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const logout = useCallback(() => {
    update(null)
    if (!config.useMocks && config.cognito.domain) {
      const params = new URLSearchParams({
        client_id: config.cognito.clientId,
        logout_uri: config.appBaseUrl,
      })
      window.location.assign(`${config.cognito.domain}/logout?${params.toString()}`)
    }
  }, [update])

  const value = useMemo<AuthContextValue>(
    () => ({ user, isLoading, loginAs, loginWithCognito, logout }),
    [user, isLoading, loginAs, loginWithCognito, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
