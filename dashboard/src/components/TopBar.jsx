import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { usePreferencesStore } from '../stores/preferencesStore'
import { useAuthStore } from '../stores/authStore'
import { Bell, Moon, Sun, Radio, Shield } from 'lucide-react'
import NotificationPanel from './NotificationPanel'
import BroadcastCompose from './BroadcastCompose'

export default function TopBar() {
  const [showNotifications, setShowNotifications] = useState(false)
  const [showBroadcast, setShowBroadcast] = useState(false)
  const darkMode = usePreferencesStore((s) => s.darkMode)
  const toggleDarkMode = usePreferencesStore((s) => s.toggleDarkMode)
  const user = useAuthStore((s) => s.user)

  const { data: stats } = useQuery({
    queryKey: ['stats'],
    queryFn: () => api.get('/stats'),
    refetchInterval: 15000,
  })

  const { data: unread } = useQuery({
    queryKey: ['unread-messages'],
    queryFn: () => api.get('/messages/unread'),
    refetchInterval: 10000,
  })

  const unreadCount = unread ? Object.values(unread).reduce((a, b) => a + b, 0) : 0

  return (
    <>
      <header className="h-14 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between px-4 z-20">
        <div className="flex items-center gap-3">
          <h1 className="text-sm font-semibold text-gray-700 dark:text-gray-300">Active Disaster Response</h1>
          {stats && (
            <span className="bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-300 text-xs font-bold px-2 py-0.5 rounded-full">
              {stats.activeIncidents} active
            </span>
          )}
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowBroadcast(true)}
            className="flex items-center gap-1.5 bg-red-600 hover:bg-red-700 text-white text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors"
          >
            <Radio className="w-3.5 h-3.5" />
            Emergency Broadcast
          </button>

          <button onClick={toggleDarkMode} className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-500 dark:text-gray-400">
            {darkMode ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
          </button>

          <button onClick={() => setShowNotifications(!showNotifications)} className="relative p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-500 dark:text-gray-400">
            <Bell className="w-4 h-4" />
            {unreadCount > 0 && (
              <span className="absolute -top-0.5 -right-0.5 w-4 h-4 bg-red-500 text-white text-[10px] rounded-full flex items-center justify-center">
                {unreadCount > 9 ? '9+' : unreadCount}
              </span>
            )}
          </button>

          <div className="flex items-center gap-3 ml-3 pl-3 border-l border-gray-200 dark:border-gray-700">
            <div className="w-9 h-9 bg-gradient-to-br from-yellow-400 via-red-500 to-purple-600 rounded-full flex items-center justify-center shadow-lg shadow-red-500/30">
              <Shield className="w-5 h-5 text-white drop-shadow" />
            </div>
            <span className="text-sm font-bold bg-gradient-to-r from-yellow-500 via-red-500 to-purple-500 bg-clip-text text-transparent hidden sm:block">ReddiBoss</span>
          </div>
        </div>
      </header>

      {showNotifications && <NotificationPanel onClose={() => setShowNotifications(false)} />}
      {showBroadcast && <BroadcastCompose onClose={() => setShowBroadcast(false)} />}
    </>
  )
}
