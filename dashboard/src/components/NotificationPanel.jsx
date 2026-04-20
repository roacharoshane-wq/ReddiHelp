import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { X, Bell, AlertTriangle } from 'lucide-react'
import { formatDistanceToNow } from 'date-fns'
import { useNavigate } from 'react-router-dom'

export default function NotificationPanel({ onClose }) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const { data: notifications = [] } = useQuery({
    queryKey: ['notifications'],
    queryFn: () => api.get('/notifications'),
  })

  const markRead = useMutation({
    mutationFn: (id) => api.patch(`/notifications/${id}/read`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['notifications'] }),
  })

  const handleClick = (n) => {
    if (!n.read) markRead.mutate(n.id)
    const data = typeof n.data === 'string' ? JSON.parse(n.data) : n.data
    if (data?.incidentId) {
      navigate(`/incidents/${data.incidentId}`)
      onClose()
    }
  }

  return (
    <div className="fixed inset-0 z-50" onClick={onClose}>
      <div
        className="absolute right-0 top-14 w-80 h-[calc(100%-56px)] bg-white dark:bg-gray-800 border-l border-gray-200 dark:border-gray-700 shadow-xl overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-3 border-b border-gray-200 dark:border-gray-700">
          <h3 className="font-semibold text-sm">Notifications</h3>
          <button onClick={onClose} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
            <X className="w-4 h-4" />
          </button>
        </div>

        {notifications.length === 0 && (
          <div className="p-8 text-center text-gray-400 text-sm">No notifications</div>
        )}

        {notifications.map((n) => (
          <div
            key={n.id}
            onClick={() => handleClick(n)}
            className={`flex items-start gap-3 p-3 border-b border-gray-100 dark:border-gray-700 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-700/50 ${!n.read ? 'bg-blue-50/50 dark:bg-blue-900/10' : ''}`}
          >
            <div className="mt-0.5">
              {n.type === 'TASK_ASSIGNED' ? <AlertTriangle className="w-4 h-4 text-orange-500" /> : <Bell className="w-4 h-4 text-blue-500" />}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xs font-medium truncate">{n.type?.replace(/_/g, ' ')}</p>
              <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                {(() => { const d = typeof n.data === 'string' ? JSON.parse(n.data) : n.data; return d?.message || '' })()}
              </p>
              <p className="text-[10px] text-gray-400 mt-0.5">
                {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
