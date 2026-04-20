import { useState, useRef } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { Package, Plus, Upload, Search, X, AlertTriangle, History, TrendingDown } from 'lucide-react'
import Papa from 'papaparse'
import toast from 'react-hot-toast'

const CATEGORY_ICONS = { food: '🍚', water: '💧', medical: '💊', shelter: '🏠', clothing: '👕', tools: '🔧', fuel: '⛽', communication: '📡', other: '📦' }

export default function ResourcesPage() {
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState(null)
  const [showAdd, setShowAdd] = useState(false)
  const [showImport, setShowImport] = useState(false)
  const queryClient = useQueryClient()

  const { data: resources = [], isLoading } = useQuery({
    queryKey: ['resources'],
    queryFn: () => api.get('/resources'),
    refetchInterval: 30000,
  })

  const filtered = resources.filter((r) => {
    if (!search) return true
    const s = search.toLowerCase()
    return (r.name || r.category || '').toLowerCase().includes(s) || (r.location || '').toLowerCase().includes(s) || (r.organisation_name || '').toLowerCase().includes(s)
  })

  const selected = resources.find((r) => r.id === selectedId)

  const stats = {
    total: resources.length,
    lowStock: resources.filter((r) => r.alert_threshold && r.quantity <= r.alert_threshold).length,
    categories: [...new Set(resources.map((r) => r.category))].length,
    totalQty: resources.reduce((s, r) => s + (r.quantity || 0), 0),
  }

  return (
    <div className="h-full flex flex-col">
      {/* Stats */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 p-4">
        <div className="grid grid-cols-4 gap-4">
          {[
            { label: 'Total Items', value: stats.total, icon: Package, color: 'text-blue-600' },
            { label: 'Low Stock', value: stats.lowStock, icon: AlertTriangle, color: 'text-red-600' },
            { label: 'Categories', value: stats.categories, icon: Package, color: 'text-purple-600' },
            { label: 'Total Quantity', value: stats.totalQty.toLocaleString(), icon: TrendingDown, color: 'text-teal-600' },
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
          <input value={search} onChange={(e) => setSearch(e.target.value)} className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" placeholder="Search resources..." />
        </div>
        <button onClick={() => setShowAdd(true)} className="flex items-center gap-1.5 px-3 py-1.5 bg-teal-600 text-white text-xs font-medium rounded-lg hover:bg-teal-700"><Plus className="w-3 h-3" />Add Resource</button>
        <button onClick={() => setShowImport(true)} className="flex items-center gap-1.5 px-3 py-1.5 border border-gray-300 dark:border-gray-600 text-xs rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"><Upload className="w-3 h-3" />Import CSV</button>
        <span className="text-xs text-gray-400 ml-auto">{filtered.length} resources</span>
      </div>

      {/* Table + Detail */}
      <div className="flex-1 flex overflow-hidden">
        <div className="flex-1 overflow-y-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-gray-800 sticky top-0">
              <tr className="text-left text-xs text-gray-500">
                <th className="px-4 py-2 font-medium">Resource</th>
                <th className="px-4 py-2 font-medium">Category</th>
                <th className="px-4 py-2 font-medium">Location</th>
                <th className="px-4 py-2 font-medium text-right">Quantity</th>
                <th className="px-4 py-2 font-medium text-right">Threshold</th>
                <th className="px-4 py-2 font-medium">Organisation</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
              {filtered.map((r) => {
                const isLow = r.alert_threshold && r.quantity <= r.alert_threshold
                return (
                  <tr key={r.id} onClick={() => setSelectedId(r.id)} className={`cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors ${selectedId === r.id ? 'bg-teal-50 dark:bg-teal-900/20' : ''} ${isLow ? 'bg-red-50/50 dark:bg-red-900/10' : ''}`}>
                    <td className="px-4 py-2.5">
                      <div className="flex items-center gap-2">
                        <span>{CATEGORY_ICONS[r.category] || '📦'}</span>
                        <span className="font-medium">{r.name || r.category}</span>
                        {isLow && <AlertTriangle className="w-3 h-3 text-red-500" />}
                      </div>
                    </td>
                    <td className="px-4 py-2.5 text-gray-500">{r.category}</td>
                    <td className="px-4 py-2.5 text-gray-500">{r.location || '—'}</td>
                    <td className={`px-4 py-2.5 text-right font-mono ${isLow ? 'text-red-600 font-bold' : ''}`}>{r.quantity?.toLocaleString()}</td>
                    <td className="px-4 py-2.5 text-right text-gray-400 font-mono">{r.alert_threshold ?? '—'}</td>
                    <td className="px-4 py-2.5 text-gray-500">{r.organisation_name || '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          {isLoading && <div className="flex items-center justify-center py-16"><div className="animate-spin w-6 h-6 border-2 border-teal-500 border-t-transparent rounded-full" /></div>}
        </div>

        {/* Detail panel */}
        {selected && <ResourceDetail resource={selected} onClose={() => setSelectedId(null)} />}
      </div>

      {showAdd && <AddResourceModal onClose={() => setShowAdd(false)} />}
      {showImport && <ImportCSVModal onClose={() => setShowImport(false)} />}
    </div>
  )
}

function ResourceDetail({ resource, onClose }) {
  const queryClient = useQueryClient()
  const [editing, setEditing] = useState(false)
  const [qty, setQty] = useState(resource.quantity)

  const { data: history = [] } = useQuery({
    queryKey: ['resource-history', resource.id],
    queryFn: () => api.get(`/resources/${resource.id}/history`),
  })

  const update = useMutation({
    mutationFn: (data) => api.patch(`/resources/${resource.id}`, data),
    onSuccess: () => { toast.success('Updated'); setEditing(false); queryClient.invalidateQueries({ queryKey: ['resources'] }) },
  })

  return (
    <div className="w-80 border-l border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-y-auto">
      <div className="p-4 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
        <div>
          <h3 className="font-bold text-sm">{resource.name || resource.category}</h3>
          <p className="text-xs text-gray-500">{resource.category}</p>
        </div>
        <button onClick={onClose} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
      </div>
      <div className="p-4 space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 text-center">
            <p className="text-2xl font-bold">{resource.quantity}</p>
            <p className="text-[10px] text-gray-500">Current Stock</p>
          </div>
          <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 text-center">
            <p className="text-2xl font-bold">{resource.alert_threshold ?? '—'}</p>
            <p className="text-[10px] text-gray-500">Alert At</p>
          </div>
        </div>

        {editing ? (
          <div className="space-y-2">
            <label className="text-xs text-gray-500">Quantity</label>
            <input type="number" value={qty} onChange={(e) => setQty(Number(e.target.value))} className="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" />
            <div className="flex gap-2">
              <button onClick={() => update.mutate({ quantity: qty })} className="flex-1 px-3 py-1.5 bg-teal-600 text-white text-xs rounded-lg">Save</button>
              <button onClick={() => setEditing(false)} className="flex-1 px-3 py-1.5 border border-gray-300 dark:border-gray-600 text-xs rounded-lg">Cancel</button>
            </div>
          </div>
        ) : (
          <button onClick={() => setEditing(true)} className="w-full px-3 py-1.5 border border-gray-300 dark:border-gray-600 text-xs rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">Edit Quantity</button>
        )}

        <div>
          <h4 className="text-xs font-medium text-gray-500 mb-2 flex items-center gap-1"><History className="w-3 h-3" />Allocation History</h4>
          <div className="space-y-2 max-h-40 overflow-y-auto">
            {history.slice(0, 10).map((h, i) => (
              <div key={i} className="flex justify-between text-xs p-2 bg-gray-50 dark:bg-gray-700/50 rounded">
                <span>{h.action}</span>
                <span className="text-gray-400">{new Date(h.created_at).toLocaleDateString()}</span>
              </div>
            ))}
            {history.length === 0 && <p className="text-xs text-gray-400 text-center">No history</p>}
          </div>
        </div>
      </div>
    </div>
  )
}

function AddResourceModal({ onClose }) {
  const queryClient = useQueryClient()
  const [form, setForm] = useState({ category: 'food', quantity: 0, location: '', name: '', alert_threshold: null, lat: null, lon: null })

  const create = useMutation({
    mutationFn: (data) => api.post('/resources', data),
    onSuccess: () => { toast.success('Resource added'); queryClient.invalidateQueries({ queryKey: ['resources'] }); onClose() },
    onError: (err) => toast.error(err.message),
  })

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" onClick={onClose}>
      <div className="bg-white dark:bg-gray-800 rounded-xl shadow-2xl w-full max-w-md mx-4" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="font-bold text-sm">Add Resource</h2>
          <button onClick={onClose} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
        </div>
        <div className="p-4 space-y-3">
          <div>
            <label className="text-xs text-gray-500">Name</label>
            <input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} className="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 mt-1" />
          </div>
          <div>
            <label className="text-xs text-gray-500">Category</label>
            <select value={form.category} onChange={(e) => setForm((f) => ({ ...f, category: e.target.value }))} className="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 mt-1">
              {Object.keys(CATEGORY_ICONS).map((c) => <option key={c} value={c}>{CATEGORY_ICONS[c]} {c}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="text-xs text-gray-500">Quantity</label><input type="number" value={form.quantity} onChange={(e) => setForm((f) => ({ ...f, quantity: Number(e.target.value) }))} className="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 mt-1" /></div>
            <div><label className="text-xs text-gray-500">Alert Threshold</label><input type="number" value={form.alert_threshold || ''} onChange={(e) => setForm((f) => ({ ...f, alert_threshold: Number(e.target.value) || null }))} className="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 mt-1" /></div>
          </div>
          <div><label className="text-xs text-gray-500">Location</label><input value={form.location} onChange={(e) => setForm((f) => ({ ...f, location: e.target.value }))} className="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 mt-1" placeholder="e.g. Kingston warehouse" /></div>
          <button onClick={() => create.mutate(form)} className="w-full py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700">Add Resource</button>
        </div>
      </div>
    </div>
  )
}

function ImportCSVModal({ onClose }) {
  const queryClient = useQueryClient()
  const fileRef = useRef(null)
  const [preview, setPreview] = useState(null)
  const [importing, setImporting] = useState(false)

  const handleFile = (e) => {
    const file = e.target.files[0]
    if (!file) return
    Papa.parse(file, {
      header: true,
      complete: (result) => setPreview(result.data.filter((r) => r.category)),
    })
  }

  const doImport = async () => {
    setImporting(true)
    try {
      const res = await api.post('/resources/bulk-import', { resources: preview })
      toast.success(`Imported ${res.inserted} resources`)
      queryClient.invalidateQueries({ queryKey: ['resources'] })
      onClose()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setImporting(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" onClick={onClose}>
      <div className="bg-white dark:bg-gray-800 rounded-xl shadow-2xl w-full max-w-lg mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="font-bold text-sm">Import CSV</h2>
          <button onClick={onClose} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded"><X className="w-4 h-4" /></button>
        </div>
        <div className="p-4 space-y-3">
          <p className="text-xs text-gray-500">CSV headers: category, quantity, location, lat, lon, name, alert_threshold</p>
          <input ref={fileRef} type="file" accept=".csv" onChange={handleFile} className="text-sm" />
          {preview && (
            <>
              <p className="text-xs text-gray-500">{preview.length} rows found</p>
              <div className="max-h-48 overflow-y-auto border border-gray-200 dark:border-gray-700 rounded-lg">
                <table className="w-full text-xs">
                  <thead><tr className="bg-gray-50 dark:bg-gray-700"><th className="px-2 py-1 text-left">Name</th><th className="px-2 py-1">Category</th><th className="px-2 py-1 text-right">Qty</th></tr></thead>
                  <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                    {preview.slice(0, 10).map((r, i) => (
                      <tr key={i}><td className="px-2 py-1">{r.name}</td><td className="px-2 py-1">{r.category}</td><td className="px-2 py-1 text-right">{r.quantity}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <button onClick={doImport} disabled={importing} className="w-full py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 disabled:opacity-50">
                {importing ? 'Importing...' : `Import ${preview.length} Resources`}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
