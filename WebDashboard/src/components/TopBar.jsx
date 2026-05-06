import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { usePreferencesStore } from '../stores/preferencesStore'
import { Bell, Moon, Sun, Radio, Shield, Menu } from 'lucide-react'
import NotificationPanel from './NotificationPanel'
import BroadcastCompose from './BroadcastCompose'

export default function TopBar({ onMenuClick, mobileNavOpen = false }) {
  const [showNotifications, setShowNotifications] = useState(false)
  const [showBroadcast, setShowBroadcast] = useState(false)
  const darkMode = usePreferencesStore((s) => s.darkMode)
  const toggleDarkMode = usePreferencesStore((s) => s.toggleDarkMode)

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
      <header className="h-14 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between px-3 sm:px-4 z-20 gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <button
            onClick={onMenuClick}
            className="md:hidden p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-500 dark:text-gray-400"
            aria-label={mobileNavOpen ? 'Close navigation' : 'Open navigation'}
          >
            <Menu className="w-4 h-4" />
          </button>

          <h1 className="text-sm font-semibold text-gray-700 dark:text-gray-300 truncate hidden sm:block">Active Disaster Response</h1>
          <h1 className="text-sm font-semibold text-gray-700 dark:text-gray-300 truncate sm:hidden">Response</h1>
          {stats && (
            <span className="bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-300 text-xs font-bold px-2 py-0.5 rounded-full shrink-0">
              {stats.activeIncidents} active
            </span>
          )}
        </div>

        <div className="flex items-center gap-1 sm:gap-2 shrink-0">
          <button
            onClick={() => setShowBroadcast(true)}
            className="flex items-center gap-1.5 bg-red-600 hover:bg-red-700 text-white text-xs font-semibold px-2 sm:px-3 py-1.5 rounded-lg transition-colors"
          >
            <Radio className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Emergency Broadcast</span>
            <span className="sm:hidden">Alert</span>
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

          <div className="flex items-center gap-2 sm:gap-3 ml-1 sm:ml-3 pl-2 sm:pl-3 border-l border-gray-200 dark:border-gray-700">
            <div className="w-9 h-9 bg-gradient-to-br from-yellow-400 via-red-500 to-purple-600 rounded-full flex items-center justify-center shadow-lg shadow-red-500/30">
              <Shield className="w-5 h-5 text-white drop-shadow" />
            </div>
            <span className="text-sm font-bold bg-gradient-to-r from-yellow-500 via-red-500 to-purple-500 bg-clip-text text-transparent hidden lg:block">ReddiBoss</span>
          </div>
        </div>
      </header>

      {showNotifications && <NotificationPanel onClose={() => setShowNotifications(false)} />}
      {showBroadcast && <BroadcastCompose onClose={() => setShowBroadcast(false)} />}
    </>
  )
}
