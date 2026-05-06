import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { ArrowLeft, UserPlus, MessageCircle, AlertTriangle, FileText, X, ChevronUp, Clock, MapPin, Users, Send } from 'lucide-react'
import toast from 'react-hot-toast'

const TYPE_ICONS = { medical: '🏥', fire: '🔥', flood: '🌊', trapped: '⚠️', shelter: '🏠', supplies: '📦', other: '📋' }
const SEV_LABELS = ['', 'Low', 'Medium', 'High', 'Critical', 'Catastrophic']
const SEV_COLORS = ['', 'text-green-600', 'text-yellow-600', 'text-orange-600', 'text-red-600', 'text-red-800']
const STATUS_NEXT = { submitted: 'active', active: 'in-progress', 'in-progress': 'resolved', assigned: 'in-progress' }

export default function IncidentDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [activeTab, setActiveTab] = useState('timeline')
  const [noteText, setNoteText] = useState('')

  const { data: incident, isLoading } = useQuery({
    queryKey: ['incident', id],
    queryFn: () => api.get(`/incidents/${id}`),
  })

  const { data: history = [] } = useQuery({
    queryKey: ['incident-history', id],
    queryFn: () => api.get(`/incidents/${id}/history`),
  })

  const transition = useMutation({
    mutationFn: (status) => api.patch(`/incidents/${id}/transition`, { status }),
    onSuccess: () => { toast.success('Status updated'); queryClient.invalidateQueries({ queryKey: ['incident', id] }); queryClient.invalidateQueries({ queryKey: ['incident-history', id] }) },
    onError: (err) => toast.error(err.message),
  })

  const addNote = useMutation({
    mutationFn: (note) => api.post(`/incidents/${id}/notes`, { note }),
    onSuccess: () => { toast.success('Note added'); setNoteText(''); queryClient.invalidateQueries({ queryKey: ['incident-history', id] }) },
  })

  if (isLoading) return <div className="flex items-center justify-center h-full"><div className="animate-spin w-8 h-8 border-2 border-teal-500 border-t-transparent rounded-full" /></div>
  if (!incident) return <div className="p-8 text-center text-gray-500">Incident not found</div>

  const nextStatus = STATUS_NEXT[incident.status]

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 py-3">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate('/incidents')} className="p-1.5 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg"><ArrowLeft className="w-4 h-4" /></button>
          <span className="text-2xl">{TYPE_ICONS[incident.type] || '📋'}</span>
          <div className="flex-1">
            <div className="flex items-baseline gap-2">
              <h1 className="text-lg font-bold">Incident #{incident.id}</h1>
              <span className="text-xs px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded">{incident.reference_number || `INC-${incident.id}`}</span>
              <span className={`text-xs font-semibold ${SEV_COLORS[incident.severity]}`}>{SEV_LABELS[incident.severity]} Severity</span>
            </div>
            <p className="text-sm text-gray-500">{incident.type} • {new Date(incident.timestamp).toLocaleString()}</p>
          </div>
        </div>

        {/* Action bar */}
        <div className="flex items-center gap-2 mt-3">
          {nextStatus && (
            <button onClick={() => transition.mutate(nextStatus)} className="flex items-center gap-1.5 px-3 py-1.5 bg-teal-600 text-white text-xs font-medium rounded-lg hover:bg-teal-700">
              <ChevronUp className="w-3 h-3" />Move to {nextStatus}
            </button>
          )}
          <button onClick={() => navigate(`/incidents?assign=${incident.id}`)} className="flex items-center gap-1.5 px-3 py-1.5 border border-gray-300 dark:border-gray-600 text-xs rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">
            <UserPlus className="w-3 h-3" />Assign
          </button>
          <button onClick={() => transition.mutate('escalated')} className="flex items-center gap-1.5 px-3 py-1.5 border border-red-300 text-red-600 text-xs rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20">
            <AlertTriangle className="w-3 h-3" />Escalate
          </button>
          {incident.status !== 'resolved' && (
            <button onClick={() => transition.mutate('resolved')} className="flex items-center gap-1.5 px-3 py-1.5 border border-green-300 text-green-600 text-xs rounded-lg hover:bg-green-50 dark:hover:bg-green-900/20 ml-auto">
              Resolve
            </button>
          )}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Left pane */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {/* Overview card */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4 space-y-3">
            <h2 className="font-semibold text-sm">Overview</h2>
            <p className="text-sm">{incident.description || 'No description provided'}</p>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div className="flex items-center gap-2"><MapPin className="w-3.5 h-3.5 text-gray-400" /><span>{incident.areaId || `${incident.lat?.toFixed(5)}, ${incident.lon?.toFixed(5)}`}</span></div>
              <div className="flex items-center gap-2"><Users className="w-3.5 h-3.5 text-gray-400" /><span>{incident.peopleAffected || '?'} people affected</span></div>
              <div className="flex items-center gap-2"><Clock className="w-3.5 h-3.5 text-gray-400" /><span>Reported {new Date(incident.timestamp).toLocaleString()}</span></div>
              <div className="flex items-center gap-2"><FileText className="w-3.5 h-3.5 text-gray-400" /><span>Status: <strong>{incident.status}</strong></span></div>
            </div>
            {incident.assignedTo && (
              <div className="bg-teal-50 dark:bg-teal-900/20 rounded-lg p-3 text-sm">
                <span className="text-gray-600 dark:text-gray-400">Assigned to:</span> <strong>{incident.responderName || `Volunteer #${incident.assignedTo}`}</strong>
              </div>
            )}
          </div>

          {/* Media */}
          {(incident.media_url || incident.imageUrl) && (
            <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
              <h2 className="font-semibold text-sm mb-2">Media</h2>
              <img src={incident.media_url || incident.imageUrl} alt="Incident" className="rounded-lg max-h-64 object-contain" />
            </div>
          )}

          {/* Tabs */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
            <div className="flex border-b border-gray-200 dark:border-gray-700 px-4">
              {['timeline', 'notes'].map((t) => (
                <button key={t} onClick={() => setActiveTab(t)} className={`px-3 py-2.5 text-xs font-medium border-b-2 -mb-px transition-colors ${activeTab === t ? 'border-teal-500 text-teal-600' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>{t.charAt(0).toUpperCase() + t.slice(1)}</button>
              ))}
            </div>
            <div className="p-4">
              {activeTab === 'timeline' && (
                <div className="space-y-3">
                  {history.map((h) => (
                    <div key={h.id} className="flex gap-3">
                      <div className="flex flex-col items-center">
                        <div className="w-2 h-2 bg-teal-500 rounded-full mt-1.5" />
                        <div className="w-px flex-1 bg-gray-200 dark:bg-gray-700" />
                      </div>
                      <div className="pb-4 flex-1">
                        <div className="flex items-baseline gap-2">
                          <span className="text-xs font-medium">{h.changed_by_name || 'System'}</span>
                          <span className="text-[10px] text-gray-400">{new Date(h.changed_at).toLocaleString()}</span>
                        </div>
                        {h.note ? (
                          <p className="text-sm text-gray-600 dark:text-gray-400 mt-0.5">{h.note}</p>
                        ) : (
                          <p className="text-sm text-gray-600 dark:text-gray-400 mt-0.5">
                            Status changed from <strong>{h.from_status}</strong> to <strong>{h.to_status}</strong>
                          </p>
                        )}
                      </div>
                    </div>
                  ))}
                  {history.length === 0 && <p className="text-sm text-gray-400 text-center py-4">No history yet</p>}
                </div>
              )}
              {activeTab === 'notes' && (
                <div className="space-y-3">
                  <div className="flex gap-2">
                    <input value={noteText} onChange={(e) => setNoteText(e.target.value)} className="flex-1 px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" placeholder="Add a note..." onKeyDown={(e) => e.key === 'Enter' && noteText.trim() && addNote.mutate(noteText.trim())} />
                    <button onClick={() => noteText.trim() && addNote.mutate(noteText.trim())} className="p-2 bg-teal-600 text-white rounded-lg hover:bg-teal-700"><Send className="w-4 h-4" /></button>
                  </div>
                  {history.filter((h) => h.note).map((h) => (
                    <div key={h.id} className="p-3 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xs font-medium">{h.changed_by_name || 'Coordinator'}</span>
                        <span className="text-[10px] text-gray-400">{new Date(h.changed_at).toLocaleString()}</span>
                      </div>
                      <p className="text-sm">{h.note}</p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
