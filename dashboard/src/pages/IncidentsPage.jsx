import { useState, useEffect, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { useSocketStore } from '../stores/socketStore'
import { useNavigate } from 'react-router-dom'
import { Search, X, UserPlus, AlertTriangle, Zap, Bot } from 'lucide-react'
import toast from 'react-hot-toast'

const TYPE_ICONS = { medical: '🏥', fire: '🔥', flood: '🌊', trapped: '⚠️', shelter: '🏠', supplies: '📦', other: '📋' }
const SEV_COLORS = ['', 'bg-green-500', 'bg-yellow-400', 'bg-orange-400', 'bg-red-500', 'bg-red-800']
const STATUS_STYLES = {
  submitted: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300',
  active: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300',
  assigned: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-300',
  'in-progress': 'bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-300',
  resolved: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300',
}

export default function IncidentsPage() {
  const [tab, setTab] = useState('queue')
  const [expandedId, setExpandedId] = useState(null)
  const [assignModalId, setAssignModalId] = useState(null)
  const [selectedIds, setSelectedIds] = useState(new Set())
  const [filters, setFilters] = useState({ statuses: [], types: [], timeRange: 'all', search: '' })
  const [sortBy, setSortBy] = useState('default')
  const [focusIndex, setFocusIndex] = useState(-1)
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const socket = useSocketStore((s) => s.socket)

  const { data: incidents = [], isLoading } = useQuery({
    queryKey: ['incidents'],
    queryFn: () => api.get('/incidents'),
    refetchInterval: 30000,
  })

  // Socket.io real-time
  useEffect(() => {
    if (!socket) return
    const refresh = () => queryClient.invalidateQueries({ queryKey: ['incidents'] })
    socket.on('incident:created', refresh)
    socket.on('incident:updated', refresh)
    socket.on('incident:escalated', refresh)
    return () => {
      socket.off('incident:created', refresh)
      socket.off('incident:updated', refresh)
      socket.off('incident:escalated', refresh)
    }
  }, [socket, queryClient])

  // Keyboard navigation (J/K/A/E) via custom events from KeyboardShortcuts
  useEffect(() => {
    const handleNext = () => setFocusIndex((prev) => { const next = Math.min(prev + 1, filtered.length - 1); if (filtered[next]) setExpandedId(filtered[next].id); return next })
    const handlePrev = () => setFocusIndex((prev) => { const next = Math.max(prev - 1, 0); if (filtered[next]) setExpandedId(filtered[next].id); return next })
    const handleAssign = () => { if (expandedId) setAssignModalId(expandedId) }
    const handleEscalate = () => {
      if (expandedId) {
        const inc = filtered.find((i) => i.id === expandedId)
        if (inc && inc.severity < 5) {
          api.patch(`/incidents/${expandedId}`, { severity: inc.severity + 1 }).then(() => queryClient.invalidateQueries({ queryKey: ['incidents'] }))
          toast.success(`Incident #${expandedId} escalated to severity ${inc.severity + 1}`)
        }
      }
    }
    window.addEventListener('kb:next-incident', handleNext)
    window.addEventListener('kb:prev-incident', handlePrev)
    window.addEventListener('kb:assign-incident', handleAssign)
    window.addEventListener('kb:escalate-incident', handleEscalate)
    return () => {
      window.removeEventListener('kb:next-incident', handleNext)
      window.removeEventListener('kb:prev-incident', handlePrev)
      window.removeEventListener('kb:assign-incident', handleAssign)
      window.removeEventListener('kb:escalate-incident', handleEscalate)
    }
  }, [filtered, expandedId, queryClient])

  // Filter and sort
  const filtered = useMemo(() => {
    let result = [...incidents]
    if (filters.statuses.length > 0) result = result.filter((i) => filters.statuses.includes(i.status))
    if (filters.types.length > 0) result = result.filter((i) => filters.types.includes(i.type))
    if (filters.search) {
      const s = filters.search.toLowerCase()
      result = result.filter((i) => (i.description || '').toLowerCase().includes(s) || (i.areaId || '').toLowerCase().includes(s) || String(i.id).includes(s))
    }
    if (filters.timeRange !== 'all') {
      const hours = { '1h': 1, '6h': 6, '24h': 24 }[filters.timeRange] || 9999
      const cutoff = new Date(Date.now() - hours * 3600000)
      result = result.filter((i) => new Date(i.timestamp) > cutoff)
    }

    if (sortBy === 'default') {
      result.sort((a, b) => {
        const aUnassigned = !a.assignedTo ? 0 : 1
        const bUnassigned = !b.assignedTo ? 0 : 1
        if (aUnassigned !== bUnassigned) return aUnassigned - bUnassigned
        if (b.severity !== a.severity) return b.severity - a.severity
        return new Date(a.timestamp) - new Date(b.timestamp)
      })
    } else if (sortBy === 'severity') result.sort((a, b) => b.severity - a.severity)
    else if (sortBy === 'time') result.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
    else if (sortBy === 'status') result.sort((a, b) => a.status.localeCompare(b.status))

    return result
  }, [incidents, filters, sortBy])

  const toggleFilter = (key, val) => {
    setFilters((f) => {
      const arr = f[key]
      return { ...f, [key]: arr.includes(val) ? arr.filter((v) => v !== val) : [...arr, val] }
    })
  }

  const timeAgo = (ts) => {
    const diff = Date.now() - new Date(ts).getTime()
    if (diff < 60000) return 'just now'
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`
    return `${Math.floor(diff / 86400000)}d ago`
  }

  const Row = ({ index, style }) => {
    const inc = filtered[index]
    if (!inc) return null
    const isExpanded = expandedId === inc.id
    const isSelected = selectedIds.has(inc.id)

    return (
      <div style={style}>
        <div
          className={`flex items-center gap-3 px-4 h-[72px] border-b border-gray-100 dark:border-gray-700 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors ${isSelected ? 'bg-teal-50 dark:bg-teal-900/20' : ''}`}
          onClick={() => setExpandedId(isExpanded ? null : inc.id)}
        >
          <input type="checkbox" checked={isSelected} onChange={(e) => { e.stopPropagation(); setSelectedIds((s) => { const n = new Set(s); n.has(inc.id) ? n.delete(inc.id) : n.add(inc.id); return n }) }} className="shrink-0" onClick={(e) => e.stopPropagation()} />
          <div className={`w-1 h-12 rounded-full shrink-0 ${SEV_COLORS[inc.severity] || 'bg-gray-300'}`} />
          <span className="text-lg shrink-0">{TYPE_ICONS[inc.type] || '📋'}</span>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium">#{inc.id}</span>
              <span className="text-sm truncate text-gray-600 dark:text-gray-400">{inc.areaId || `${inc.lat?.toFixed(3)}, ${inc.lon?.toFixed(3)}`}</span>
            </div>
            <p className="text-xs text-gray-500 truncate">{inc.description}</p>
          </div>
          <span className="text-xs text-gray-400 shrink-0 w-16 text-right">{timeAgo(inc.timestamp)}</span>
          <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0 ${STATUS_STYLES[inc.status] || ''}`}>{inc.status}</span>
          <span className={`text-xs shrink-0 w-24 text-right truncate ${inc.assignedTo ? 'text-gray-600 dark:text-gray-400' : 'text-red-500 font-medium'}`}>
            {inc.responderName || (inc.assignedTo ? `#${inc.assignedTo}` : 'Unassigned')}
          </span>
        </div>

        {isExpanded && <ExpandedRow incident={inc} onAssign={() => setAssignModalId(inc.id)} onNavigate={() => navigate(`/incidents/${inc.id}`)} />}
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col">
      {/* Tabs */}
      <div className="flex items-center gap-1 px-4 pt-3 pb-2 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
        {[
          { key: 'queue', label: 'Incident Queue', icon: AlertTriangle },
          { key: 'dispatch', label: 'AI Dispatch', icon: Bot },
        ].map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg transition-colors ${tab === t.key ? 'bg-teal-50 dark:bg-teal-900/30 text-teal-700 dark:text-teal-300' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'}`}
          >
            <t.icon className="w-3.5 h-3.5" />
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'queue' ? (
        <>
          {/* Filter bar */}
          <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 py-2 flex flex-wrap items-center gap-2">
            <div className="relative flex-1 min-w-48 max-w-sm">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
              <input
                value={filters.search}
                onChange={(e) => setFilters((f) => ({ ...f, search: e.target.value }))}
                className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700"
                placeholder="Search incidents..."
              />
            </div>

            <div className="flex gap-1">
              {['active', 'in-progress', 'resolved'].map((s) => (
                <button key={s} onClick={() => toggleFilter('statuses', s)} className={`px-2 py-1 text-[10px] font-medium rounded-full border transition-colors ${filters.statuses.includes(s) ? 'bg-teal-100 dark:bg-teal-900/40 border-teal-300 text-teal-700' : 'border-gray-200 dark:border-gray-600 text-gray-500'}`}>
                  {s}
                </button>
              ))}
            </div>

            <div className="flex gap-1">
              {['1h', '6h', '24h', 'all'].map((t) => (
                <button key={t} onClick={() => setFilters((f) => ({ ...f, timeRange: t }))} className={`px-2 py-1 text-[10px] font-medium rounded-full border ${filters.timeRange === t ? 'bg-teal-100 dark:bg-teal-900/40 border-teal-300 text-teal-700' : 'border-gray-200 dark:border-gray-600 text-gray-500'}`}>
                  {t === 'all' ? 'All' : `Last ${t}`}
                </button>
              ))}
            </div>

            {(filters.statuses.length > 0 || filters.types.length > 0 || filters.search || filters.timeRange !== 'all') && (
              <button onClick={() => setFilters({ statuses: [], types: [], timeRange: 'all', search: '' })} className="text-[10px] text-red-500 hover:text-red-600">Clear all</button>
            )}

            <span className="text-xs text-gray-400 ml-auto">{filtered.length} incidents</span>
          </div>

          {/* Bulk actions */}
          {selectedIds.size > 0 && (
            <div className="bg-teal-50 dark:bg-teal-900/20 border-b border-teal-200 dark:border-teal-800 px-4 py-2 flex items-center gap-3">
              <span className="text-xs font-medium text-teal-700 dark:text-teal-300">{selectedIds.size} selected</span>
              <button onClick={() => { api.patch('/incidents/bulk', { ids: [...selectedIds], status: 'resolved' }).then(() => { toast.success('Bulk update done'); queryClient.invalidateQueries({ queryKey: ['incidents'] }); setSelectedIds(new Set()) }) }} className="text-xs px-2 py-1 bg-green-600 text-white rounded">Bulk Close</button>
              <button onClick={() => setSelectedIds(new Set())} className="text-xs text-gray-500 hover:text-gray-700">Deselect all</button>
            </div>
          )}

          {/* List */}
          <div className="flex-1">
            {isLoading ? (
              <div className="flex items-center justify-center h-full"><div className="animate-spin w-6 h-6 border-2 border-teal-500 border-t-transparent rounded-full" /></div>
            ) : (
              <div className="overflow-y-auto" style={{ maxHeight: 'calc(100vh - 200px)' }}>
                {filtered.map((inc, index) => <Row key={inc.id} index={index} style={{}} />)}
              </div>
            )}
          </div>
        </>
      ) : (
        <AIDispatchTab />
      )}

      {assignModalId && <AssignModal incidentId={assignModalId} onClose={() => setAssignModalId(null)} />}
    </div>
  )
}

function ExpandedRow({ incident, onAssign, onNavigate }) {
  const { data: history = [] } = useQuery({
    queryKey: ['incident-history', incident.id],
    queryFn: () => api.get(`/incidents/${incident.id}/history`),
  })

  return (
    <div className="bg-gray-50 dark:bg-gray-800/50 border-b border-gray-200 dark:border-gray-700 px-4 py-3 space-y-3">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <p className="text-xs font-medium text-gray-500 mb-1">Description</p>
          <p className="text-sm">{incident.description || 'No description'}</p>
          <p className="text-xs text-gray-500 mt-2">People affected: {incident.peopleAffected || 'Unknown'}</p>
          <p className="text-xs text-gray-500">Ref: {incident.reference_number || `INC-${incident.id}`}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-gray-500 mb-1">Timeline</p>
          <div className="space-y-1 max-h-32 overflow-y-auto">
            {history.map((h) => (
              <div key={h.id} className="text-xs flex items-center gap-2">
                <span className="w-1.5 h-1.5 rounded-full bg-teal-400 shrink-0" />
                <span className="text-gray-500">{h.changed_by_name || 'System'}</span>
                <span>{h.note || `${h.from_status} → ${h.to_status}`}</span>
              </div>
            ))}
            {history.length === 0 && <p className="text-xs text-gray-400">No history yet</p>}
          </div>
        </div>
      </div>
      <div className="flex gap-2">
        <button onClick={onAssign} className="flex items-center gap-1 px-3 py-1.5 bg-teal-600 text-white text-xs rounded-lg hover:bg-teal-700"><UserPlus className="w-3 h-3" />Assign</button>
        <button onClick={onNavigate} className="px-3 py-1.5 text-xs border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">View Details</button>
        <button onClick={() => { api.patch(`/incidents/${incident.id}/transition`, { status: 'escalated' }).then(() => toast.success('Escalated')) }} className="px-3 py-1.5 text-xs text-red-600 border border-red-300 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20">Escalate</button>
      </div>
    </div>
  )
}

function AssignModal({ incidentId, onClose }) {
  const queryClient = useQueryClient()
  const [search, setSearch] = useState('')

  const { data: volunteers = [], isLoading } = useQuery({
    queryKey: ['volunteers'],
    queryFn: () => api.get('/volunteers/list'),
  })

  const assign = useMutation({
    mutationFn: (volunteerId) => api.post(`/incidents/${incidentId}/assign`, { volunteerId }),
    onSuccess: () => { toast.success('Assigned!'); queryClient.invalidateQueries({ queryKey: ['incidents'] }); onClose() },
    onError: (err) => toast.error(err.message),
  })

  const filtered = volunteers.filter((v) => {
    if (!search) return true
    const s = search.toLowerCase()
    return (v.username || '').toLowerCase().includes(s) || (v.phone || '').includes(s) || (v.skills || []).some((sk) => sk.toLowerCase().includes(s))
  })

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" onClick={onClose}>
      <div className="bg-white dark:bg-gray-800 rounded-xl shadow-2xl w-full max-w-md mx-4 max-h-[80vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="font-bold text-sm">Assign Incident #{incidentId}</h2>
          <button onClick={onClose} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
        </div>
        <div className="px-4 pt-3 pb-2">
          <div className="relative">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
            <input value={search} onChange={(e) => setSearch(e.target.value)} className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" placeholder="Search by name or skill..." />
          </div>
        </div>
        <div className="flex-1 overflow-y-auto p-4 pt-2 space-y-2">
          {isLoading && <div className="text-center py-8"><div className="animate-spin w-6 h-6 border-2 border-teal-500 border-t-transparent rounded-full mx-auto" /></div>}
          {filtered.map((v) => (
            <div key={v.id} className="flex items-center gap-3 p-3 border border-gray-200 dark:border-gray-700 rounded-lg hover:border-teal-300 dark:hover:border-teal-600 transition-colors">
              <div className="relative shrink-0">
                <div className="w-9 h-9 bg-teal-100 dark:bg-teal-900/40 rounded-full flex items-center justify-center text-sm font-bold text-teal-700">{(v.username || v.phone || '?')[0].toUpperCase()}</div>
                <div className={`absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-white dark:border-gray-800 ${v.availability === 'available' ? 'bg-green-500' : v.availability === 'busy' ? 'bg-orange-400' : 'bg-gray-400'}`} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium truncate">{v.username || v.phone}</span>
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-gray-100 dark:bg-gray-700 text-gray-500">{v.availability}</span>
                </div>
                {v.skills && v.skills.length > 0 && (
                  <div className="flex flex-wrap gap-1 mt-1">
                    {v.skills.map((sk) => <span key={sk} className="text-[10px] px-1.5 py-0.5 bg-teal-50 dark:bg-teal-900/30 text-teal-700 dark:text-teal-300 rounded">{sk}</span>)}
                  </div>
                )}
                {(!v.skills || v.skills.length === 0) && <p className="text-[10px] text-gray-400 mt-0.5">{v.role}</p>}
              </div>
              <button onClick={() => assign.mutate(v.id)} className="px-3 py-1.5 bg-teal-600 text-white text-xs rounded-lg hover:bg-teal-700 shrink-0">Assign</button>
            </div>
          ))}
          {!isLoading && filtered.length === 0 && <p className="text-sm text-gray-500 text-center py-4">No volunteers found</p>}
        </div>
      </div>
    </div>
  )
}

function AIDispatchTab() {
  const queryClient = useQueryClient()
  const [result, setResult] = useState(null)
  const [running, setRunning] = useState(false)

  const { data: decisions = [] } = useQuery({
    queryKey: ['dispatch-decisions'],
    queryFn: () => api.get('/dispatch-decisions'),
  })

  const runDispatch = async () => {
    setRunning(true)
    try {
      const res = await api.post('/auto-dispatch/run', {})
      setResult(res)
      queryClient.invalidateQueries({ queryKey: ['incidents'] })
      toast.success(`Auto-assigned: ${res.auto_assigned.length}, Needs approval: ${res.needs_approval.length}`)
    } catch (err) {
      toast.error(err.message)
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-bold text-lg">AI Dispatch Engine</h2>
          <p className="text-sm text-gray-500">Automatically assigns volunteers to unassigned incidents based on distance, skills, and availability</p>
        </div>
        <button onClick={runDispatch} disabled={running} className="flex items-center gap-2 px-4 py-2 bg-teal-600 hover:bg-teal-700 text-white text-sm font-medium rounded-lg disabled:opacity-50">
          {running ? <div className="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full" /> : <Zap className="w-4 h-4" />}
          {running ? 'Running...' : 'Run Auto-Dispatch'}
        </button>
      </div>

      {result && (
        <div className="grid grid-cols-3 gap-4">
          <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-xl p-4">
            <h3 className="text-sm font-semibold text-green-700 dark:text-green-300 mb-2">Auto-Assigned ({result.auto_assigned.length})</h3>
            {result.auto_assigned.map((a) => (
              <div key={a.incidentId} className="text-xs py-1">Incident #{a.incidentId} → {a.volunteerName} ({a.confidence}%)</div>
            ))}
          </div>
          <div className="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-xl p-4">
            <h3 className="text-sm font-semibold text-amber-700 dark:text-amber-300 mb-2">Needs Approval ({result.needs_approval.length})</h3>
            {result.needs_approval.map((a) => (
              <div key={a.incidentId} className="text-xs py-1 flex items-center justify-between">
                <span>#{a.incidentId} → {a.volunteerName} ({a.confidence}%)</span>
                <button onClick={() => { api.post(`/incidents/${a.incidentId}/assign`, { volunteerId: a.volunteerId }).then(() => toast.success('Approved!')) }} className="text-teal-600 hover:text-teal-700 font-medium">Approve</button>
              </div>
            ))}
          </div>
          <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl p-4">
            <h3 className="text-sm font-semibold text-red-700 dark:text-red-300 mb-2">Manual Review ({result.manual_review.length})</h3>
            {result.manual_review.map((a) => (
              <div key={a.incidentId} className="text-xs py-1">#{a.incidentId}: {a.reason}</div>
            ))}
          </div>
        </div>
      )}

      <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
        <div className="p-3 border-b border-gray-200 dark:border-gray-700">
          <h3 className="font-semibold text-sm">Recent Dispatch Decisions</h3>
        </div>
        <div className="divide-y divide-gray-100 dark:divide-gray-700">
          {decisions.slice(0, 20).map((d) => (
            <div key={d.id} className="flex items-center gap-3 p-3 text-sm">
              <span className={`w-2 h-2 rounded-full ${d.decision === 'auto_assigned' ? 'bg-green-500' : d.decision === 'needs_approval' ? 'bg-amber-400' : 'bg-red-500'}`} />
              <span className="text-gray-600 dark:text-gray-400">Incident #{d.incident_id}</span>
              <span>→</span>
              <span>{d.volunteer_name || `#${d.volunteer_id}`}</span>
              <span className="text-xs px-1.5 py-0.5 bg-gray-100 dark:bg-gray-700 rounded">{d.confidence}%</span>
              <span className="text-xs text-gray-400 ml-auto">{d.decision?.replace('_', ' ')}</span>
            </div>
          ))}
          {decisions.length === 0 && <p className="text-sm text-gray-400 p-4 text-center">No dispatch decisions yet</p>}
        </div>
      </div>
    </div>
  )
}
