import { useQuery } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { Shield, AlertTriangle, Users, Activity, Radio } from 'lucide-react'

const API = import.meta.env.VITE_API_URL || ''

export default function PublicStatusPage() {
  const [lastUpdate, setLastUpdate] = useState(new Date())

  const { data: status, isLoading } = useQuery({
    queryKey: ['public-status'],
    queryFn: async () => {
      const res = await fetch(`${API}/api/public/status`)
      if (!res.ok) throw new Error('Failed to load')
      return res.json()
    },
    refetchInterval: 30000,
  })

  useEffect(() => {
    if (status) setLastUpdate(new Date())
  }, [status])

  const overallStatus = !status ? 'loading' : (status.activeIncidents || 0) > 10 ? 'critical' : (status.activeIncidents || 0) > 5 ? 'elevated' : 'normal'
  const statusConfig = {
    loading: { label: 'Loading...', color: 'bg-gray-100 text-gray-600', icon: Activity },
    normal: { label: 'Normal Operations', color: 'bg-green-100 text-green-700', icon: Shield },
    elevated: { label: 'Elevated Activity', color: 'bg-amber-100 text-amber-700', icon: AlertTriangle },
    critical: { label: 'Critical Level', color: 'bg-red-100 text-red-700', icon: AlertTriangle },
  }

  const cfg = statusConfig[overallStatus]

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b shadow-sm">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-teal-600 rounded-xl flex items-center justify-center"><Radio className="w-5 h-5 text-white" /></div>
            <div>
              <h1 className="font-bold text-lg">ReddiHelp Status</h1>
              <p className="text-xs text-gray-500">Public disaster response status dashboard</p>
            </div>
          </div>
          <p className="text-xs text-gray-400">Last updated: {lastUpdate.toLocaleTimeString()}</p>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        {/* Overall status */}
        <div className={`rounded-2xl p-6 flex items-center gap-4 ${cfg.color}`}>
          <cfg.icon className="w-10 h-10" />
          <div>
            <h2 className="text-2xl font-bold">{cfg.label}</h2>
            <p className="text-sm opacity-80">Current disaster response operational status for Jamaica</p>
          </div>
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-16"><div className="animate-spin w-8 h-8 border-2 border-teal-500 border-t-transparent rounded-full" /></div>
        ) : status ? (
          <>
            {/* Metrics */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {[
                { label: 'Active Incidents', value: status.activeIncidents ?? 0, icon: AlertTriangle },
                { label: 'Responders Online', value: status.respondersOnline ?? 0, icon: Users },
                { label: 'Resolved Today', value: status.resolvedToday ?? 0, icon: Shield },
                { label: 'Avg Response', value: status.avgResponseMin ? `${status.avgResponseMin}m` : '—', icon: Activity },
              ].map((m) => (
                <div key={m.label} className="bg-white rounded-xl border border-gray-200 p-4 text-center">
                  <m.icon className="w-6 h-6 mx-auto mb-2 text-gray-400" />
                  <p className="text-3xl font-black">{m.value}</p>
                  <p className="text-xs text-gray-500 mt-1">{m.label}</p>
                </div>
              ))}
            </div>

            {/* Recent broadcasts */}
            {status.recentBroadcasts?.length > 0 && (
              <div className="bg-white rounded-xl border border-gray-200 p-4">
                <h3 className="font-semibold text-sm mb-3">Recent Public Announcements</h3>
                <div className="space-y-3">
                  {status.recentBroadcasts.map((b, i) => (
                    <div key={i} className="p-3 bg-gray-50 rounded-lg">
                      <div className="flex items-center gap-2 mb-1">
                        <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${b.severity === 'critical' ? 'bg-red-100 text-red-700' : b.severity === 'warning' ? 'bg-amber-100 text-amber-700' : 'bg-blue-100 text-blue-700'}`}>{b.severity || 'info'}</span>
                        <span className="text-xs text-gray-400">{new Date(b.created_at).toLocaleString()}</span>
                      </div>
                      <p className="text-sm">{b.message}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Info */}
            <div className="bg-white rounded-xl border border-gray-200 p-4 text-center">
              <p className="text-sm text-gray-500">If you need emergency assistance, call <strong>119</strong> or report via the ReddiHelp mobile app.</p>
            </div>
          </>
        ) : (
          <p className="text-center text-gray-500">Unable to load status data</p>
        )}
      </div>
    </div>
  )
}
