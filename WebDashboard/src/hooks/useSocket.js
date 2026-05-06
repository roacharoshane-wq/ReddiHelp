import { useEffect } from 'react'
import { io } from 'socket.io-client'
import { useSocketStore } from '../stores/socketStore'
import { useAuthStore } from '../stores/authStore'

const SOCKET_URL = (() => {
  const socketUrl = (import.meta.env.VITE_SOCKET_URL || '').trim()
  if (socketUrl) return socketUrl.replace(/\/+$/, '')

  const apiUrl = (import.meta.env.VITE_API_URL || '').trim().replace(/\/+$/, '')
  if (apiUrl) return apiUrl.replace(/\/api$/, '')

  return typeof window !== 'undefined' ? window.location.origin : ''
})()

if (!SOCKET_URL) {
  console.error('CRITICAL: Unable to resolve socket URL. Check VITE_SOCKET_URL and VITE_API_URL.')
}

export function useSocket() {
  const { socket, setSocket, setConnected } = useSocketStore()
  const accessToken = useAuthStore((s) => s.accessToken)

  useEffect(() => {
    if (!SOCKET_URL || socket) return

    const s = io(SOCKET_URL, {
      auth: { token: accessToken },
      transports: ['websocket', 'polling'],
    })

    s.on('connect', () => setConnected(true))
    s.on('disconnect', () => setConnected(false))
    setSocket(s)

    return () => {
      s.disconnect()
      setSocket(null)
      setConnected(false)
    }
  }, [accessToken])

  return socket
}