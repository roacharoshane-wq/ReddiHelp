import { useAuthStore } from '../stores/authStore'

const BASE = '/api'

async function request(path, options = {}) {
  const token = useAuthStore.getState().accessToken
  const headers = { 'Content-Type': 'application/json', ...options.headers }
  if (token) headers['Authorization'] = `Bearer ${token}`

  let res = await fetch(`${BASE}${path}`, { ...options, headers })

  if (res.status === 401) {
    const refreshToken = useAuthStore.getState().refreshToken
    if (refreshToken) {
      const refreshRes = await fetch(`${BASE}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken }),
      })
      if (refreshRes.ok) {
        const { accessToken } = await refreshRes.json()
        useAuthStore.getState().setAccessToken(accessToken)
        headers['Authorization'] = `Bearer ${accessToken}`
        res = await fetch(`${BASE}${path}`, { ...options, headers })
      } else {
        useAuthStore.getState().logout()
        window.location.href = '/login'
        throw new Error('Session expired')
      }
    }
  }

  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }))
    throw new Error(err.error || res.statusText)
  }
  return res.json()
}

export const api = {
  get: (path) => request(path),
  post: (path, data) => request(path, { method: 'POST', body: JSON.stringify(data) }),
  patch: (path, data) => request(path, { method: 'PATCH', body: JSON.stringify(data) }),
  delete: (path) => request(path, { method: 'DELETE' }),
}
