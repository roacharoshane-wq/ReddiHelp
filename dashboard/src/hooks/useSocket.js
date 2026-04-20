import { useEffect } from 'react'
import { io } from 'socket.io-client'
import { useSocketStore } from '../stores/socketStore'
import { useAuthStore } from '../stores/authStore'

export function useSocket() {
  const { socket, setSocket, setConnected } = useSocketStore()
  const accessToken = useAuthStore((s) => s.accessToken)

  useEffect(() => {
    if (socket) return

    const s = io(window.location.origin, {
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
