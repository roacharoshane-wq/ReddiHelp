import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { useAuthStore } from '../stores/authStore'
import { Clock, Loader, CheckCircle, Activity, CircleAlert, X } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

export default function DashboardPage() {
  const user = useAuthStore((s) => s.user)
  const navigate = useNavigate()
  const [expandedKpi, setExpandedKpi] = useState(null)

  const { data: stats } = useQuery({
    queryKey: ['stats'],
    queryFn: () => api.get('/stats'),
    refetchInterval: 15000,
  })

  const { data: health } = useQuery({
    queryKey: ['health-score'],
    queryFn: () => api.get('/analytics/health-score'),
    refetchInterval: 30000,
  })

  const { data: incidents = [] } = useQuery({
    queryKey: ['incidents'],
    queryFn: () => api.get('/incidents'),
    refetchInterval: 30000,
  })

  const { data: volunteers = [] } = useQuery({
    queryKey: ['volunteers'],
    queryFn: () => api.get('/volunteers/list'),
    refetchInterval: 30000,
  })

  const recentIncidents = incidents.slice(0, 8)
  const healthColor = { green: 'bg-green-100 text-green-700 border-green-300', amber: 'bg-amber-100 text-amber-700 border-amber-300', red: 'bg-red-100 text-red-700 border-red-300' }
  const healthEmoji = { green: '✅', amber: '⚠️', red: '🚨' }

  const kpis = [
    { key: 'unassigned', label: 'Unassigned', value: incidents.filter(i => !i.assignedTo && i.status !== 'resolved').length, icon: CircleAlert, color: 'text-red-500', bg: 'bg-red-50 dark:bg-red-900/20', filter: (i) => !i.assignedTo && i.status !== 'resolved' },
    { key: 'total', label: 'Total Incidents', value: stats?.totalIncidents || 0, icon: Activity, color: 'text-blue-500', bg: 'bg-blue-50 dark:bg-blue-900/20', filter: () => true },
    { key: 'inprogress', label: 'In Progress', value: incidents.filter(i => i.status === 'in-progress').length, icon: Loader, color: 'text-orange-500', bg: 'bg-orange-50 dark:bg-orange-900/20', filter: (i) => i.status === 'in-progress' },
    { key: 'resolved', label: 'Resolved', value: stats?.resolvedIncidents || 0, icon: CheckCircle, color: 'text-teal-500', bg: 'bg-teal-50 dark:bg-teal-900/20', filter: (i) => i.status === 'resolved' },
  ]

  const expandedData = expandedKpi ? kpis.find(k => k.key === expandedKpi) : null
  const expandedIncidents = expandedData ? incidents.filter(expandedData.filter) : []

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Welcome back, ReddiBoss</h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">Here's your operational overview</p>
        </div>
        {health && (
          <div className={`px-4 py-2 rounded-xl border text-sm font-bold ${healthColor[health.score] || healthColor.green}`}>
            {healthEmoji[health.score]} System Health: {health.score?.toUpperCase()}
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {kpis.map((kpi) => (
          <div key={kpi.key} onClick={() => setExpandedKpi(expandedKpi === kpi.key ? null : kpi.key)} className={`${kpi.bg} rounded-xl p-4 border cursor-pointer transition-all hover:shadow-md ${expandedKpi === kpi.key ? 'border-teal-400 dark:border-teal-500 ring-2 ring-teal-200 dark:ring-teal-800' : 'border-gray-200 dark:border-gray-700'}`}>
            <div className="flex items-center justify-between">
              <kpi.icon className={`w-5 h-5 ${kpi.color}`} />
              <span className="text-2xl font-bold">{kpi.value}</span>
            </div>
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">{kpi.label}</p>
          </div>
        ))}
      </div>

      {expandedKpi && expandedData && (
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
          <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
            <h2 className="font-semibold text-sm">{expandedData.label} ({expandedIncidents.length})</h2>
            <button onClick={() => setExpandedKpi(null)} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
          </div>
          <div className="divide-y divide-gray-100 dark:divide-gray-700 max-h-80 overflow-y-auto">
            {expandedIncidents.map((inc) => (
              <div key={inc.id} onClick={() => navigate(`/incidents/${inc.id}`)} className="flex items-center gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer">
                <div className={`w-2 h-8 rounded-full ${inc.severity >= 4 ? 'bg-red-500' : inc.severity >= 3 ? 'bg-orange-400' : inc.severity >= 2 ? 'bg-yellow-400' : 'bg-green-400'}`} />
                <span className="text-xs font-mono text-gray-400 w-8">#{inc.id}</span>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{inc.type} — {inc.areaId || 'Unknown area'}</p>
                  <p className="text-xs text-gray-500 truncate">{inc.description}</p>
                </div>
                <span className="text-xs text-gray-400">{inc.responderName || (inc.assignedTo ? `#${inc.assignedTo}` : 'Unassigned')}</span>
                <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${inc.status === 'active' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' : inc.status === 'resolved' ? 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' : 'bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-300'}`}>
                  {inc.status}
                </span>
              </div>
            ))}
            {expandedIncidents.length === 0 && <p className="text-sm text-gray-400 text-center py-6">No incidents</p>}
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
          <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
            <h2 className="font-semibold text-sm">Recent Incidents</h2>
            <button onClick={() => navigate('/incidents')} className="text-xs text-teal-600 hover:text-teal-700">View all</button>
          </div>
          <div className="divide-y divide-gray-100 dark:divide-gray-700">
            {recentIncidents.map((inc) => (
              <div key={inc.id} onClick={() => navigate(`/incidents/${inc.id}`)} className="flex items-center gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer">
                <div className={`w-2 h-8 rounded-full ${inc.severity >= 4 ? 'bg-red-500' : inc.severity >= 3 ? 'bg-orange-400' : inc.severity >= 2 ? 'bg-yellow-400' : 'bg-green-400'}`} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{inc.type} — {inc.areaId || 'Unknown area'}</p>
                  <p className="text-xs text-gray-500 truncate">{inc.description}</p>
                </div>
                <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${inc.status === 'active' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' : inc.status === 'resolved' ? 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' : 'bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-300'}`}>
                  {inc.status}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
          <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
            <h2 className="font-semibold text-sm">Active Volunteers</h2>
            <button onClick={() => navigate('/volunteers')} className="text-xs text-teal-600 hover:text-teal-700">View all</button>
          </div>
          <div className="divide-y divide-gray-100 dark:divide-gray-700">
            {volunteers.slice(0, 8).map((v) => (
              <div key={v.id} className="flex items-center gap-3 p-3">
                <div className={`w-2.5 h-2.5 rounded-full ${v.availability === 'available' ? 'bg-green-500' : v.availability === 'on_task' ? 'bg-blue-500' : 'bg-gray-400'}`} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">{v.username || v.phone}</p>
                  <p className="text-xs text-gray-500">{v.role} • {v.availability}</p>
                </div>
                <span className="text-xs text-gray-400">{v.active_tasks || 0} tasks</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
