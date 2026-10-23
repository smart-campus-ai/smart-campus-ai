import type { ReactElement, ReactNode } from 'react'
import { render } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { ApiContext } from '@/api/context'
import type { ApiClient } from '@/domain/api'
import { MockApi } from '@/api/mock'
import type { MockIdentity } from '@/api/mock'
import { AuthContext } from '@/auth/context'
import type { AuthContextValue, AuthUser } from '@/auth/types'

interface Options {
  api?: ApiClient
  identity?: MockIdentity
  route?: string
  initialEntries?: Array<string | { pathname: string; state?: unknown }>
  user?: AuthUser | null
}

/** Render a component wrapped with react-query + router + an injectable API client. */
export function renderWithProviders(ui: ReactElement, options: Options = {}) {
  const identity: MockIdentity =
    options.identity ?? { sub: 'student-001', email: 'alice@esiea.fr', role: 'student' }
  const api = options.api ?? new MockApi(identity)
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })

  const entries = options.initialEntries ?? [options.route ?? '/']

  const authValue: AuthContextValue = {
    user:
      options.user !== undefined
        ? options.user
        : { sub: identity.sub, email: identity.email, role: identity.role, token: '' },
    isLoading: false,
    loginAs: () => {},
    loginWithCognito: async () => {},
    logout: () => {},
  }

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <MemoryRouter initialEntries={entries as never}>
        <QueryClientProvider client={queryClient}>
          <AuthContext.Provider value={authValue}>
            <ApiContext.Provider value={api}>{children}</ApiContext.Provider>
          </AuthContext.Provider>
        </QueryClientProvider>
      </MemoryRouter>
    )
  }

  return { api, ...render(ui, { wrapper: Wrapper }) }
}
