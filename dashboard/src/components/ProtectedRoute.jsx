import { useAuthStore } from '../stores/authStore'

export default function ProtectedRoute({ children }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  // With MOCK_AUTH, we auto-authenticate
  if (!isAuthenticated) {
    // Auto-login for MOCK_AUTH dev mode
    const { login } = useAuthStore.getState()
    login({
      user: { id: 1, username: 'admin', phone: '+18761234567', role: 'coordinator' },
      accessToken: 'mock-token',
      refreshToken: 'mock-refresh',
    })
  }
  return children
}
