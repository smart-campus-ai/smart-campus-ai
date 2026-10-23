import { useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { config } from '@/lib/config'
import type { ApiClient } from '@/domain/api'
import { HttpApi } from '@/api/http'
import { MockApi } from '@/api/mock'
import type { MockIdentity } from '@/api/mock'
import { ApiContext } from '@/api/context'
import { AuthProvider } from '@/auth/AuthProvider'
import type { AuthUser } from '@/auth/types'

function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, staleTime: 10_000 },
    },
  })
}

/**
 * Wires auth + API client + react-query. In mock mode the same MockApi
 * instance is reused and its identity follows the logged-in user so that
 * ownership rules (BOLA, admin-only) are enforced client-side.
 */
export function AppProviders({ children }: { children: ReactNode }) {
  const [queryClient] = useState(createQueryClient)

  // Stable mock instance across renders (keeps in-memory state).
  const mockRef = useRef<MockApi | null>(null)
  const tokenRef = useRef<string | null>(null)

  const api = useMemo<ApiClient>(() => {
    if (config.useMocks) {
      mockRef.current ??= new MockApi({
        sub: 'anonymous',
        email: '',
        role: 'student',
      })
      return mockRef.current
    }
    return new HttpApi(() => tokenRef.current)
  }, [])

  const handleUserChange = (user: AuthUser | null) => {
    tokenRef.current = user?.token ?? null
    if (config.useMocks && mockRef.current) {
      const identity: MockIdentity = user
        ? { sub: user.sub, email: user.email, role: user.role }
        : { sub: 'anonymous', email: '', role: 'student' }
      mockRef.current.setIdentity(identity)
    }
  }

  return (
    <QueryClientProvider client={queryClient}>
      <ApiContext.Provider value={api}>
        <AuthProvider onUserChange={handleUserChange}>{children}</AuthProvider>
      </ApiContext.Provider>
    </QueryClientProvider>
  )
}
