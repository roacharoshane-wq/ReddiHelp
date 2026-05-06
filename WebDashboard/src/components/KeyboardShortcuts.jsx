import { useEffect, useCallback, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { usePreferencesStore } from '../stores/preferencesStore'
import { X } from 'lucide-react'

export default function KeyboardShortcuts() {
  const { selectedIncidentId, setSelectedIncidentId } = usePreferencesStore()
  const navigate = useNavigate()
  const [showHelp, setShowHelp] = useState(false)

  const handleKeyDown = useCallback((e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) return

    switch (e.key) {
      case 'j':
        // Navigate to next incident
        window.dispatchEvent(new CustomEvent('kb:next-incident'))
        break
      case 'k':
        // Navigate to previous incident
        window.dispatchEvent(new CustomEvent('kb:prev-incident'))
        break
      case 'Enter':
        // Open selected incident detail
        if (selectedIncidentId) {
          navigate(`/incidents/${selectedIncidentId}`)
        }
        break
      case 'a':
        if (!e.ctrlKey && !e.metaKey) {
          // Quick-assign selected incident
          window.dispatchEvent(new CustomEvent('kb:assign-incident'))
        }
        break
      case 'e':
        // Quick-escalate selected incident
        window.dispatchEvent(new CustomEvent('kb:escalate-incident'))
        break
      case '?':
        setShowHelp(prev => !prev)
        break
      case 'Escape':
        if (showHelp) {
          setShowHelp(false)
        } else {
          setSelectedIncidentId(null)
        }
        break
    }
  }, [selectedIncidentId, navigate, setSelectedIncidentId, showHelp])

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [handleKeyDown])

  if (!showHelp) return null

  const shortcuts = [
    { key: 'J', desc: 'Next incident' },
    { key: 'K', desc: 'Previous incident' },
    { key: 'Enter', desc: 'Open incident detail' },
    { key: 'A', desc: 'Quick-assign selected incident' },
    { key: 'E', desc: 'Escalate selected incident' },
    { key: 'Esc', desc: 'Deselect / close' },
    { key: '?', desc: 'Toggle this help' },
  ]

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowHelp(false)}>
      <div className="bg-white dark:bg-gray-800 rounded-xl shadow-2xl p-6 w-96 max-w-[90vw]" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold">Keyboard Shortcuts</h2>
          <button onClick={() => setShowHelp(false)} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="space-y-2">
          {shortcuts.map(({ key, desc }) => (
            <div key={key} className="flex items-center justify-between py-1.5">
              <span className="text-sm text-gray-600 dark:text-gray-400">{desc}</span>
              <kbd className="px-2 py-1 text-xs font-mono bg-gray-100 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded">{key}</kbd>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
