import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { Radio, ChevronDown, ChevronUp, Users, Clock, AlertTriangle } from 'lucide-react'

const SEV_COLORS = { critical: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300', warning: 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-300', info: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300' }

export default function BroadcastsPage() {
  const [expandedId, setExpandedId] = useState(null)

  const { data: broadcasts = [], isLoading } = useQuery({
    queryKey: ['broadcasts'],
    queryFn: () => api.get('/broadcasts'),
    refetchInterval: 30000,
  })

  const stats = {
    total: broadcasts.length,
    critical: broadcasts.filter((b) => b.severity === 'critical').length,
    last24h: broadcasts.filter((b) => new Date(b.created_at) > new Date(Date.now() - 86400000)).length,
    totalRecipients: broadcasts.reduce((s, b) => s + (b.recipient_count || 0), 0),
  }

  return (
    <div className="h-full flex flex-col">
      {/* Stats */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 p-4">
        <div className="grid grid-cols-4 gap-4">
          {[
            { label: 'Total Broadcasts', value: stats.total, icon: Radio, color: 'text-blue-600' },
            { label: 'Critical', value: stats.critical, icon: AlertTriangle, color: 'text-red-600' },
            { label: 'Last 24h', value: stats.last24h, icon: Clock, color: 'text-orange-600' },
            { label: 'Total Recipients', value: stats.totalRecipients.toLocaleString(), icon: Users, color: 'text-teal-600' },
          ].map((s) => (
            <div key={s.label} className="flex items-center gap-3">
              <div className={`p-2 rounded-lg bg-gray-100 dark:bg-gray-700 ${s.color}`}><s.icon className="w-5 h-5" /></div>
              <div><p className="text-xl font-bold">{s.value}</p><p className="text-[10px] text-gray-500">{s.label}</p></div>
            </div>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-16"><div className="animate-spin w-6 h-6 border-2 border-teal-500 border-t-transparent rounded-full" /></div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-gray-800 sticky top-0">
              <tr className="text-left text-xs text-gray-500">
                <th className="px-4 py-2 font-medium w-8" />
                <th className="px-4 py-2 font-medium">Title / Message</th>
                <th className="px-4 py-2 font-medium">Severity</th>
                <th className="px-4 py-2 font-medium">Type</th>
                <th className="px-4 py-2 font-medium text-right">Recipients</th>
                <th className="px-4 py-2 font-medium text-right">Delivered</th>
                <th className="px-4 py-2 font-medium">Sent</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
              {broadcasts.map((b) => (
                <>
                  <tr key={b.id} onClick={() => setExpandedId(expandedId === b.id ? null : b.id)} className="cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors">
                    <td className="px-4 py-3">{expandedId === b.id ? <ChevronUp className="w-3.5 h-3.5 text-gray-400" /> : <ChevronDown className="w-3.5 h-3.5 text-gray-400" />}</td>
                    <td className="px-4 py-3">
                      <p className="font-medium">{b.title || 'Broadcast'}</p>
                      <p className="text-xs text-gray-500 truncate max-w-sm">{b.message}</p>
                    </td>
                    <td className="px-4 py-3"><span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${SEV_COLORS[b.severity] || SEV_COLORS.info}`}>{b.severity || 'info'}</span></td>
                    <td className="px-4 py-3 text-gray-500">{b.type || 'general'}</td>
                    <td className="px-4 py-3 text-right font-mono">{b.recipient_count || '—'}</td>
                    <td className="px-4 py-3 text-right font-mono">{b.delivery_count || '—'}</td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{new Date(b.created_at).toLocaleString()}</td>
                  </tr>
                  {expandedId === b.id && (
                    <tr key={`${b.id}-detail`}>
                      <td colSpan={7} className="bg-gray-50 dark:bg-gray-800/50 px-4 py-4">
                        <div className="max-w-2xl space-y-2">
                          <p className="text-sm">{b.message}</p>
                          {b.areaId && <p className="text-xs text-gray-500">Target area: {b.areaId}</p>}
                          {b.recipient_count != null && (
                            <div className="flex items-center gap-4 text-xs text-gray-500">
                              <span>Recipients: {b.recipient_count}</span>
                              <span>Delivered: {b.delivery_count || 0}</span>
                              <span>Rate: {b.recipient_count ? ((b.delivery_count || 0) / b.recipient_count * 100).toFixed(0) : 0}%</span>
                            </div>
                          )}
                          <p className="text-[10px] text-gray-400">Sent by coordinator #{b.sent_by} at {new Date(b.created_at).toLocaleString()}</p>
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </table>
        )}
        {!isLoading && broadcasts.length === 0 && <p className="text-sm text-gray-400 text-center py-16">No broadcasts sent yet</p>}
      </div>
    </div>
  )
}
