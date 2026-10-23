/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_USE_MOCKS?: string
  readonly VITE_API_BASE_URL?: string
  readonly VITE_APP_BASE_URL?: string
  readonly VITE_COGNITO_DOMAIN?: string
  readonly VITE_COGNITO_CLIENT_ID?: string
  readonly VITE_COGNITO_SCOPE?: string
  readonly VITE_COGNITO_REDIRECT_URI?: string
  readonly VITE_COGNITO_ENTRA_IDP?: string
  readonly VITE_ENABLE_ENTRA_FEDERATION?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
