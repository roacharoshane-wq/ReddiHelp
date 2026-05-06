import { useState, useRef, useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { FileText, Download, Loader2 } from 'lucide-react'
import html2canvas from 'html2canvas'
import jsPDF from 'jspdf'

export default function ReportsPage() {
  const queryClient = useQueryClient()
  const reportRef = useRef(null)
  const [dateRange, setDateRange] = useState({ start: new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10), end: new Date().toISOString().slice(0, 10) })
  const [typeFilter, setTypeFilter] = useState('all')
  const [generating, setGenerating] = useState(false)

  const { data: report, refetch: genReport, isFetching } = useQuery({
    queryKey: ['report-generate', dateRange, typeFilter],
    queryFn: () => api.get(`/reports/generate?start=${dateRange.start}&end=${dateRange.end}${typeFilter !== 'all' ? `&type=${typeFilter}` : ''}`),
    enabled: false,
  })

  const { data: savedReports = [] } = useQuery({
    queryKey: ['saved-reports'],
    queryFn: () => api.get('/reports'),
  })

  const saveReport = useMutation({
    mutationFn: (data) => api.post('/reports', data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['saved-reports'] }),
  })

  const handleGenerate = async () => {
    setGenerating(true)
    await genReport()
    setGenerating(false)
  }

  const downloadPDF = useCallback(async () => {
    if (!reportRef.current) return
    const canvas = await html2canvas(reportRef.current, { scale: 2, useCORS: true, backgroundColor: '#ffffff' })
    const imgData = canvas.toDataURL('image/png')
    const pdf = new jsPDF('p', 'mm', 'a4')
    const w = pdf.internal.pageSize.getWidth()
    const h = (canvas.height * w) / canvas.width
    pdf.addImage(imgData, 'PNG', 0, 0, w, h)
    pdf.save(`incident-report-${dateRange.start}-${dateRange.end}.pdf`)

    saveReport.mutate({
      title: `Report ${dateRange.start} to ${dateRange.end}`,
      date_range_start: dateRange.start,
      date_range_end: dateRange.end,
      type_filter: typeFilter,
      summary: report,
    })
  }, [report, dateRange, typeFilter, saveReport])

  return (
    <div className="h-full flex flex-col">
      {/* Controls */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 p-4">
        <h1 className="text-lg font-bold mb-3">Post-Incident Report Generator</h1>
        <div className="flex items-end gap-4">
          <div>
            <label className="text-xs text-gray-500 block mb-1">Start Date</label>
            <input type="date" value={dateRange.start} onChange={(e) => setDateRange((d) => ({ ...d, start: e.target.value }))} className="px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" />
          </div>
          <div>
            <label className="text-xs text-gray-500 block mb-1">End Date</label>
            <input type="date" value={dateRange.end} onChange={(e) => setDateRange((d) => ({ ...d, end: e.target.value }))} className="px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700" />
          </div>
          <div>
            <label className="text-xs text-gray-500 block mb-1">Incident Type</label>
            <select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} className="px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700">
              <option value="all">All types</option>
              {['medical', 'fire', 'flood', 'trapped', 'shelter', 'supplies', 'other'].map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </div>
          <button onClick={handleGenerate} disabled={generating || isFetching} className="flex items-center gap-1.5 px-4 py-1.5 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 disabled:opacity-50">
            {(generating || isFetching) ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <FileText className="w-3.5 h-3.5" />}
            Generate Report
          </button>
          {report && (
            <button onClick={downloadPDF} className="flex items-center gap-1.5 px-4 py-1.5 border border-gray-300 dark:border-gray-600 text-sm rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">
              <Download className="w-3.5 h-3.5" />Export PDF
            </button>
          )}
        </div>
      </div>

      {/* Report content */}
      <div className="flex-1 overflow-y-auto">
        {report ? (
          <div ref={reportRef} className="max-w-4xl mx-auto p-6 space-y-6">
            {/* Report header */}
            <div className="border-b border-gray-200 dark:border-gray-700 pb-4">
              <h2 className="text-xl font-bold">Incident Report</h2>
              <p className="text-sm text-gray-500">{dateRange.start} to {dateRange.end} {typeFilter !== 'all' ? `• ${typeFilter} incidents only` : ''}</p>
              <p className="text-xs text-gray-400 mt-1">Generated {new Date().toLocaleString()}</p>
            </div>

            {/* Summary stats */}
            <div className="grid grid-cols-4 gap-4">
              {[
                { label: 'Total Incidents', value: report.totalIncidents ?? 0 },
                { label: 'Resolved', value: report.resolved ?? 0 },
                { label: 'Avg Response (min)', value: report.avgResponseMinutes ?? '—' },
                { label: 'Volunteers Deployed', value: report.volunteersDeployed ?? 0 },
              ].map((s) => (
                <div key={s.label} className="bg-gray-50 dark:bg-gray-700/50 rounded-xl p-4 text-center">
                  <p className="text-2xl font-bold">{s.value}</p>
                  <p className="text-xs text-gray-500 mt-1">{s.label}</p>
                </div>
              ))}
            </div>

            {/* By type */}
            {report.byType && (
              <div>
                <h3 className="font-semibold text-sm mb-2">By Incident Type</h3>
                <table className="w-full text-sm">
                  <thead><tr className="text-left text-xs text-gray-500 border-b"><th className="py-2">Type</th><th className="py-2 text-right">Count</th><th className="py-2 text-right">Resolved</th><th className="py-2 text-right">Avg Severity</th></tr></thead>
                  <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                    {report.byType.map((t) => (
                      <tr key={t.type}><td className="py-2">{t.type}</td><td className="py-2 text-right">{t.count}</td><td className="py-2 text-right">{t.resolved}</td><td className="py-2 text-right">{Number(t.avgSeverity).toFixed(1)}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {/* By area */}
            {report.byArea && (
              <div>
                <h3 className="font-semibold text-sm mb-2">By Area</h3>
                <table className="w-full text-sm">
                  <thead><tr className="text-left text-xs text-gray-500 border-b"><th className="py-2">Area</th><th className="py-2 text-right">Count</th></tr></thead>
                  <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                    {report.byArea.map((a) => (
                      <tr key={a.area}><td className="py-2">{a.area}</td><td className="py-2 text-right">{a.count}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {/* Resource usage */}
            {report.resourceUsage && (
              <div>
                <h3 className="font-semibold text-sm mb-2">Resource Usage</h3>
                <div className="grid grid-cols-3 gap-3">
                  {report.resourceUsage.map((r) => (
                    <div key={r.category} className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
                      <p className="text-sm font-medium">{r.category}</p>
                      <p className="text-xs text-gray-500">{r.totalAllocated ?? 0} allocated of {r.totalQuantity ?? 0}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <FileText className="w-12 h-12 mb-3 opacity-30" />
            <p className="text-sm">Select a date range and generate a report</p>
          </div>
        )}

        {/* Saved reports */}
        {savedReports.length > 0 && (
          <div className="max-w-4xl mx-auto p-6 border-t border-gray-200 dark:border-gray-700 mt-6">
            <h3 className="font-semibold text-sm mb-3">Previously Generated Reports</h3>
            <div className="space-y-2">
              {savedReports.map((r) => (
                <div key={r.id} className="flex items-center gap-3 p-3 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
                  <FileText className="w-4 h-4 text-gray-400" />
                  <span className="text-sm font-medium flex-1">{r.title}</span>
                  <span className="text-xs text-gray-400">{new Date(r.created_at).toLocaleString()}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
