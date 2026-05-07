import { useAuthStore } from '../stores/authStore'
import { Navigate } from 'react-router-dom'

const MOCK_AUTH = (import.meta.env.VITE_MOCK_AUTH || '').toLowerCase() === 'true'

export default function ProtectedRoute({ children }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)

  if (!isAuthenticated) {
    if (MOCK_AUTH) {
      const { login } = useAuthStore.getState()
      login({
        user: { id: 1, username: 'admin', phone: '+18761234567', role: 'coordinator' },
        accessToken: 'mock-token',
        refreshToken: 'mock-refresh',
      })
      return children
    }

    return <Navigate to="/login" replace />
  }

  return children
}
