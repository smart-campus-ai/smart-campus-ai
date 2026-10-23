/** PKCE + minimal JWT helpers for the Cognito authorization-code flow (SPA, no secret). */

function base64UrlEncode(bytes: Uint8Array): string {
  let str = ''
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function randomVerifier(length = 64): string {
  const bytes = new Uint8Array(length)
  crypto.getRandomValues(bytes)
  return base64UrlEncode(bytes)
}

export async function challengeFromVerifier(verifier: string): Promise<string> {
  const data = new TextEncoder().encode(verifier)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return base64UrlEncode(new Uint8Array(digest))
}

/** Decode a JWT payload without verifying the signature (verification is the API's job). */
export function decodeJwt(token: string): Record<string, unknown> {
  const [, payload] = token.split('.')
  if (!payload) return {}
  const normalized = payload.replace(/-/g, '+').replace(/_/g, '/')
  const json = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '='))
  try {
    return JSON.parse(json) as Record<string, unknown>
  } catch {
    return {}
  }
}
