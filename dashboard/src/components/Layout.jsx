import { Outlet } from 'react-router-dom'
import Sidebar from './Sidebar'
import TopBar from './TopBar'
import { usePreferencesStore } from '../stores/preferencesStore'
import { useSocket } from '../hooks/useSocket'
import KeyboardShortcuts from './KeyboardShortcuts'

export default function Layout() {
  const collapsed = usePreferencesStore((s) => s.sidebarCollapsed)
  useSocket()

  return (
    <div className={`flex h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-gray-100`}>
      <Sidebar />
      <div className={`flex flex-col flex-1 transition-all duration-200 ${collapsed ? 'ml-16' : 'ml-60'}`}>
        <TopBar />
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
      <KeyboardShortcuts />
    </div>
  )
}
