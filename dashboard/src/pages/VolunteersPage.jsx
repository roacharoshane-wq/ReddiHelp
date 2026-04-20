import { useState, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { useSocketStore } from '../stores/socketStore'
import { Search, Grid, List as ListIcon, MapPin, Phone, X, Activity, Users, Clock, Award } from 'lucide-react'

const AVAIL_COLORS = { available: 'bg-green-500', busy: 'bg-orange-400', offline: 'bg-gray-400', dispatched: 'bg-blue-500' }
const ROLE_BADGES = { medical_professional: '🏥', fire_rescue: '🚒', search_rescue: '🔍', logistics: '📦', general: '🤝' }

export default function VolunteersPage() {
  const [search, setSearch] = useState('')
  const [view, setView] = useState('list')
  const [selectedId, setSelectedId] = useState(null)
  const [statusFilter, setStatusFilter] = useState('all')
  const socket = useSocketStore((s) => s.socket)

  const { data: volunteers = [], isLoading, refetch } = useQuery({
    queryKey: ['volunteers'],
    queryFn: () => api.get('/volunteers/list'),
    refetchInterval: 15000,
  })

  useEffect(() => {
    if (!socket) return
    const handler = () => refetch()
    socket.on('volunteer:location', handler)
    socket.on('volunteer:status', handler)
    return () => { socket.off('volunteer:location', handler); socket.off('volunteer:status', handler) }
  }, [socket, refetch])

  const filtered = volunteers.filter((v) => {
    if (statusFilter !== 'all' && v.availability !== statusFilter) return false
    if (search) {
      const s = search.toLowerCase()
      return (v.username || '').toLowerCase().includes(s) || (v.phone || '').includes(s) || (v.role || '').toLowerCase().includes(s)
    }
    return true
  })

  const stats = {
    total: volunteers.length,
    available: volunteers.filter((v) => v.availability === 'available').length,
    busy: volunteers.filter((v) => v.availability === 'busy' || v.availability === 'dispatched').length,
    avgTasks: volunteers.length ? (volunteers.reduce((s, v) => s + (v.total_completed || 0), 0) / volunteers.length).toFixed(1) : '0',
  }

  const selected = volunteers.find((v) => v.id === selectedId)

  return (
    <div className="h-full flex flex-col">
      {/* Header stats */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 p-4">
        <div className="grid grid-cols-4 gap-4">
          {[
            { label: 'Total Volunteers', value: stats.total, icon: Users, color: 'text-blue-600' },
            { label: 'Available Now', value: stats.available, icon: Activity, color: 'text-green-600' },
            { label: 'On Task', value: stats.busy, icon: Clock, color: 'text-orange-600' },
            { label: 'Avg Completed', value: stats.avgTasks, icon: Award, color: 'text-purple-600' },
          ].map((s) => (
            <div key={s.label} className="flex items-center gap-3">
              <div className={`p-2 rounded-lg bg-gray-100 dark:bg-gray-700 ${s.color}`}><s.icon className="w-5 h-5" /></div>
              <div><p className="text-xl font-bold">{s.value}</p><p className="text-[10px] text-gray-500">{s.label}</p></div>
            </div>
          ))}
        </div>
      </div>

      {/* Toolbar */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 py-2 flex items-center gap-2">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
          <input value={search} onChange={(e) => setSearch(e.target.value)} className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" placeholder="Search volunteers..." />
        </div>
        <div className="flex gap-1">
          {['all', 'available', 'busy', 'offline'].map((s) => (
            <button key={s} onClick={() => setStatusFilter(s)} className={`px-2.5 py-1 text-[10px] font-medium rounded-full border transition-colors ${statusFilter === s ? 'bg-teal-100 dark:bg-teal-900/40 border-teal-300 text-teal-700' : 'border-gray-200 dark:border-gray-600 text-gray-500'}`}>{s}</button>
          ))}
        </div>
        <div className="ml-auto flex gap-1 border border-gray-200 dark:border-gray-600 rounded-lg overflow-hidden">
          <button onClick={() => setView('list')} className={`p-1.5 ${view === 'list' ? 'bg-teal-100 dark:bg-teal-900/40' : ''}`}><ListIcon className="w-3.5 h-3.5" /></button>
          <button onClick={() => setView('grid')} className={`p-1.5 ${view === 'grid' ? 'bg-teal-100 dark:bg-teal-900/40' : ''}`}><Grid className="w-3.5 h-3.5" /></button>
        </div>
        <span className="text-xs text-gray-400">{filtered.length} volunteers</span>
      </div>

      {/* Main content */}
      <div className="flex-1 flex overflow-hidden">
        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <div className="flex items-center justify-center h-full"><div className="animate-spin w-6 h-6 border-2 border-teal-500 border-t-transparent rounded-full" /></div>
          ) : view === 'grid' ? (
            <div className="p-4 grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
              {filtered.map((v) => (
                <div key={v.id} onClick={() => setSelectedId(v.id)} className={`p-3 rounded-xl border cursor-pointer transition-all hover:shadow-md ${selectedId === v.id ? 'border-teal-500 shadow-md' : 'border-gray-200 dark:border-gray-700'} bg-white dark:bg-gray-800`}>
                  <div className="flex items-center gap-2 mb-2">
                    <div className="relative">
                      <div className="w-10 h-10 bg-teal-100 dark:bg-teal-900/40 rounded-full flex items-center justify-center text-sm font-bold text-teal-700">{(v.username || v.phone || '?')[0].toUpperCase()}</div>
                      <div className={`absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full border-2 border-white dark:border-gray-800 ${AVAIL_COLORS[v.availability] || 'bg-gray-400'}`} />
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{v.username || v.phone}</p>
                      <p className="text-[10px] text-gray-500">{ROLE_BADGES[v.role] || ''} {v.role}</p>
                    </div>
                  </div>
                  <div className="flex gap-2 text-[10px] text-gray-500">
                    <span>{v.active_tasks || 0} active</span>
                    <span>{v.total_completed || 0} done</span>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="overflow-y-auto" style={{ maxHeight: 'calc(100vh - 200px)' }}>
              {filtered.map((v) => (
                <div key={v.id} onClick={() => setSelectedId(v.id)} className={`flex items-center gap-3 px-4 h-14 border-b border-gray-100 dark:border-gray-700 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 ${selectedId === v.id ? 'bg-teal-50 dark:bg-teal-900/20' : ''}`}>
                  <div className="relative shrink-0">
                    <div className="w-8 h-8 bg-teal-100 dark:bg-teal-900/40 rounded-full flex items-center justify-center text-xs font-bold text-teal-700">{(v.username || v.phone || '?')[0].toUpperCase()}</div>
                    <div className={`absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-white dark:border-gray-900 ${AVAIL_COLORS[v.availability] || 'bg-gray-400'}`} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{v.username || v.phone}</p>
                    <p className="text-[10px] text-gray-500">{v.role}</p>
                  </div>
                  <span className="text-[10px] text-gray-400 w-20 text-right">{v.active_tasks || 0} tasks</span>
                  <span className="text-[10px] text-gray-400 w-20 text-right">{v.total_completed || 0} done</span>
                  {v.last_lat && <span className="text-[10px] text-gray-400 w-20 text-right"><MapPin className="w-3 h-3 inline" /></span>}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Detail panel */}
        {selected && (
          <div className="w-80 border-l border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-y-auto">
            <div className="p-4 border-b border-gray-200 dark:border-gray-700 flex justify-between items-start">
              <div className="flex items-center gap-3">
                <div className="relative">
                  <div className="w-12 h-12 bg-teal-100 dark:bg-teal-900/40 rounded-full flex items-center justify-center text-lg font-bold text-teal-700">{(selected.username || selected.phone || '?')[0].toUpperCase()}</div>
                  <div className={`absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full border-2 border-white dark:border-gray-800 ${AVAIL_COLORS[selected.availability] || 'bg-gray-400'}`} />
                </div>
                <div>
                  <h3 className="font-bold text-sm">{selected.username || selected.phone}</h3>
                  <p className="text-xs text-gray-500">{selected.role} • {selected.availability}</p>
                </div>
              </div>
              <button onClick={() => setSelectedId(null)} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
            </div>
            <div className="p-4 space-y-3">
              {selected.phone && (
                <div className="flex items-center gap-2 text-sm">
                  <Phone className="w-3.5 h-3.5 text-gray-400" />
                  <span>{selected.phone}</span>
                </div>
              )}
              {selected.last_lat && (
                <div className="flex items-center gap-2 text-sm">
                  <MapPin className="w-3.5 h-3.5 text-gray-400" />
                  <span>{selected.last_lat?.toFixed(4)}, {selected.last_lon?.toFixed(4)}</span>
                </div>
              )}
              {selected.last_location_at && (
                <p className="text-[10px] text-gray-400 ml-6">Last seen: {new Date(selected.last_location_at).toLocaleString()}</p>
              )}
              <div className="grid grid-cols-2 gap-3 pt-2">
                <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 text-center">
                  <p className="text-lg font-bold">{selected.active_tasks || 0}</p>
                  <p className="text-[10px] text-gray-500">Active Tasks</p>
                </div>
                <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 text-center">
                  <p className="text-lg font-bold">{selected.total_completed || 0}</p>
                  <p className="text-[10px] text-gray-500">Completed</p>
                </div>
              </div>
              {selected.skills && selected.skills.length > 0 && (
                <div>
                  <p className="text-xs font-medium text-gray-500 mb-1">Skills</p>
                  <div className="flex flex-wrap gap-1">
                    {selected.skills.map((s) => <span key={s} className="text-[10px] px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded-full">{s}</span>)}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
