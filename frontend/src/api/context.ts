import { createContext, useContext } from 'react'
import type { ApiClient } from '@/domain/api'

export const ApiContext = createContext<ApiClient | null>(null)

export function useApi(): ApiClient {
  const api = useContext(ApiContext)
  if (!api) throw new Error('useApi must be used within <ApiProvider>')
  return api
}
