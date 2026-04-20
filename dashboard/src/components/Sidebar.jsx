import { NavLink } from 'react-router-dom'
import { usePreferencesStore } from '../stores/preferencesStore'
import {
  Map, AlertTriangle, Users, Package, Radio,
  LayoutDashboard, ChevronLeft, ChevronRight, Zap, X,
  BarChart3, FileText
} from 'lucide-react'

const navItems = [
  { to: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/map', icon: Map, label: 'Map' },
  { to: '/incidents', icon: AlertTriangle, label: 'Incidents' },
  { to: '/volunteers', icon: Users, label: 'Volunteers' },
  { to: '/resources', icon: Package, label: 'Resources' },
  { to: '/broadcasts', icon: Radio, label: 'Broadcasts' },
  { to: '/analytics', icon: BarChart3, label: 'Analytics' },
  { to: '/reports', icon: FileText, label: 'Reports' },
]

export default function Sidebar({ mobileOpen = false, onCloseMobile = () => {} }) {
  const collapsed = usePreferencesStore((s) => s.sidebarCollapsed)
  const toggleSidebar = usePreferencesStore((s) => s.toggleSidebar)
  const showLabels = mobileOpen || !collapsed

  return (
    <>
      <div
        onClick={onCloseMobile}
        className={`fixed inset-0 z-30 bg-black/40 transition-opacity md:hidden ${mobileOpen ? 'opacity-100' : 'pointer-events-none opacity-0'}`}
      />

      <aside
        className={`fixed top-0 left-0 z-40 h-full bg-white dark:bg-gray-800 border-r border-gray-200 dark:border-gray-700 transition-all duration-200 flex flex-col w-72 md:w-auto ${mobileOpen ? 'translate-x-0' : '-translate-x-full'} md:translate-x-0 ${collapsed ? 'md:w-16' : 'md:w-60'}`}
      >
        <div className="flex items-center justify-between h-14 px-4 border-b border-gray-200 dark:border-gray-700">
          <div className="flex items-center min-w-0">
            <Zap className="w-6 h-6 text-teal-500 shrink-0" />
            {showLabels && <span className="ml-2 font-bold text-lg text-teal-600 dark:text-teal-400 truncate">ReddiHelp</span>}
          </div>
          <button
            onClick={onCloseMobile}
            className="md:hidden p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-500"
            aria-label="Close navigation"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <nav className="flex-1 py-2 space-y-1 overflow-y-auto">
          {navItems.map(({ to, icon: Icon, label }) => (
            <NavLink
              key={to}
              to={to}
              onClick={onCloseMobile}
              className={({ isActive }) =>
                `flex items-center px-4 py-2.5 mx-2 rounded-lg transition-colors text-sm font-medium ${
                  isActive
                    ? 'bg-teal-50 dark:bg-teal-900/30 text-teal-700 dark:text-teal-300'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
                }`
              }
            >
              <Icon className="w-5 h-5 shrink-0" />
              {showLabels && <span className="ml-3 truncate">{label}</span>}
            </NavLink>
          ))}
        </nav>

        <button
          onClick={toggleSidebar}
          className="hidden md:flex items-center justify-center h-10 border-t border-gray-200 dark:border-gray-700 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
        >
          {collapsed ? <ChevronRight className="w-4 h-4" /> : <ChevronLeft className="w-4 h-4" />}
        </button>
      </aside>
    </>
  )
}
