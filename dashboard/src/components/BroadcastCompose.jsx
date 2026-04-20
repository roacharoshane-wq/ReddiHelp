import { useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { api } from '../api/client'
import { X, Send, AlertTriangle } from 'lucide-react'
import toast from 'react-hot-toast'

export default function BroadcastCompose({ onClose }) {
  const [title, setTitle] = useState('')
  const [message, setMessage] = useState('')
  const [severity, setSeverity] = useState('INFO')
  const [confirmText, setConfirmText] = useState('')
  const [step, setStep] = useState('compose') // compose | confirm | sending

  const sendBroadcast = useMutation({
    mutationFn: (data) => api.post('/broadcasts/geographic', data),
    onSuccess: (result) => {
      toast.success(`Broadcast sent to ${result.affectedUserCount} users`)
      onClose()
    },
    onError: (err) => toast.error(err.message),
  })

  const handleSend = () => {
    if (step === 'compose') {
      if (!message.trim()) return toast.error('Message required')
      setStep('confirm')
      return
    }
    if (confirmText !== 'CONFIRM') return
    sendBroadcast.mutate({ message: `[${severity}] ${title ? title + ': ' : ''}${message}`, targetRoles: 'all' })
    setStep('sending')
  }

  const sevColors = { INFO: 'bg-blue-100 text-blue-700 border-blue-300', WARNING: 'bg-amber-100 text-amber-700 border-amber-300', CRITICAL: 'bg-red-100 text-red-700 border-red-300' }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" onClick={onClose}>
      <div className="bg-white dark:bg-gray-800 rounded-xl shadow-2xl w-full max-w-lg mx-4" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="font-bold text-lg flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-red-500" />
            Emergency Broadcast
          </h2>
          <button onClick={onClose} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
        </div>

        <div className="p-4 space-y-4">
          {step === 'compose' && (
            <>
              <div>
                <label className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1 block">Title (optional)</label>
                <input
                  value={title} onChange={(e) => setTitle(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm"
                  placeholder="Alert title..."
                />
              </div>

              <div>
                <label className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1 block">Severity</label>
                <div className="flex gap-2">
                  {['INFO', 'WARNING', 'CRITICAL'].map((s) => (
                    <button
                      key={s}
                      onClick={() => setSeverity(s)}
                      className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${severity === s ? sevColors[s] : 'border-gray-200 dark:border-gray-600 text-gray-500'}`}
                    >
                      {s}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1 block">Message ({message.length}/500)</label>
                <textarea
                  value={message} onChange={(e) => setMessage(e.target.value.slice(0, 500))}
                  rows={4}
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm resize-none"
                  placeholder="Broadcast message..."
                />
              </div>
            </>
          )}

          {step === 'confirm' && (
            <div className="text-center space-y-3">
              <div className={`inline-block px-4 py-2 rounded-lg text-sm font-semibold ${sevColors[severity]}`}>{severity}</div>
              <p className="text-sm">You are about to send a broadcast to <strong>all users</strong>.</p>
              <p className="text-xs text-gray-500">Type <strong>CONFIRM</strong> to proceed:</p>
              <input
                value={confirmText} onChange={(e) => setConfirmText(e.target.value)}
                className="w-48 mx-auto px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-sm text-center"
                placeholder="Type CONFIRM"
              />
            </div>
          )}

          {step === 'sending' && (
            <div className="text-center py-8">
              <div className="animate-spin w-8 h-8 border-2 border-teal-500 border-t-transparent rounded-full mx-auto mb-3" />
              <p className="text-sm text-gray-500">Sending broadcast...</p>
            </div>
          )}
        </div>

        {step !== 'sending' && (
          <div className="flex justify-end gap-2 p-4 border-t border-gray-200 dark:border-gray-700">
            <button onClick={step === 'confirm' ? () => setStep('compose') : onClose} className="px-4 py-2 text-sm rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">
              {step === 'confirm' ? 'Back' : 'Cancel'}
            </button>
            <button
              onClick={handleSend}
              disabled={step === 'confirm' && confirmText !== 'CONFIRM'}
              className="flex items-center gap-1.5 px-4 py-2 bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white text-sm font-medium rounded-lg"
            >
              <Send className="w-3.5 h-3.5" />
              {step === 'confirm' ? 'Send Broadcast' : 'Review & Send'}
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
