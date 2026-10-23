/**
 * Runtime configuration read from Vite env variables (VITE_*).
 *
 * The app ships with mocks enabled by default so the whole SPA runs locally
 * without any AWS backend. Set the VITE_* variables (see .env.example) to wire
 * the real API Gateway + Cognito user pool.
 */

function bool(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value === '') return fallback
  return value === 'true' || value === '1'
}

export const config = {
  /** When true, the API layer uses the in-memory mock adapter (no network). */
  useMocks: bool(import.meta.env.VITE_USE_MOCKS, true),

  /** Base URL of the REST API. Behind CloudFront this is "/api". */
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL ?? '/api',

  /** Public CloudFront URL of the environment, used for shareable links (US09). */
  appBaseUrl: import.meta.env.VITE_APP_BASE_URL ?? window.location.origin,

  cognito: {
    /** Cognito Hosted UI domain, e.g. https://sc-dev.auth.us-east-1.amazoncognito.com */
    domain: import.meta.env.VITE_COGNITO_DOMAIN ?? '',
    clientId: import.meta.env.VITE_COGNITO_CLIENT_ID ?? '',
    /** OAuth scopes requested during the authorization-code + PKCE flow. */
    scope: import.meta.env.VITE_COGNITO_SCOPE ?? 'openid email profile',
    /** Redirect URI registered on the app client. */
    redirectUri:
      import.meta.env.VITE_COGNITO_REDIRECT_URI ??
      `${window.location.origin}/auth/callback`,
    /** Identity provider name for the Entra ID federation (US06). */
    entraIdpName: import.meta.env.VITE_COGNITO_ENTRA_IDP ?? '',
  },

  /** US06 — show the "Se connecter avec Microsoft" button only when enabled. */
  enableEntraFederation: bool(import.meta.env.VITE_ENABLE_ENTRA_FEDERATION, false),
} as const

export type AppConfig = typeof config
