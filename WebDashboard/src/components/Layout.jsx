import { useEffect, useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from './Sidebar'
import TopBar from './TopBar'
import { usePreferencesStore } from '../stores/preferencesStore'
import { useSocket } from '../hooks/useSocket'
import KeyboardShortcuts from './KeyboardShortcuts'

export default function Layout() {
  const location = useLocation()
  const collapsed = usePreferencesStore((s) => s.sidebarCollapsed)
  const [mobileNavOpen, setMobileNavOpen] = useState(false)

  useSocket()

  useEffect(() => {
    setMobileNavOpen(false)
  }, [location.pathname])

  return (
    <div className="flex min-h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-gray-100">
      <Sidebar mobileOpen={mobileNavOpen} onCloseMobile={() => setMobileNavOpen(false)} />
      <div className={`flex min-w-0 flex-1 flex-col transition-all duration-200 ${collapsed ? 'md:ml-16' : 'md:ml-60'}`}>
        <TopBar onMenuClick={() => setMobileNavOpen((open) => !open)} mobileNavOpen={mobileNavOpen} />
        <main className="flex-1 overflow-x-hidden overflow-y-auto">
          <Outlet />
        </main>
      </div>
      <KeyboardShortcuts />
    </div>
  )
}
