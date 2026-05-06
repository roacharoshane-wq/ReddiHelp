import { useState, useRef, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { LineChart, Line, BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend, AreaChart, Area } from 'recharts'
import { Activity, Clock, Users, Package, Download, TrendingUp, Shield } from 'lucide-react'
import html2canvas from 'html2canvas'
import jsPDF from 'jspdf'

const COLORS = ['#14b8a6', '#f59e0b', '#ef4444', '#8b5cf6', '#3b82f6', '#22c55e', '#ec4899', '#06b6d4']

export default function AnalyticsPage() {
  const [timeRange, setTimeRange] = useState('7d')
  const reportRef = useRef(null)

  const rangeToHours = { '24h': 24, '7d': 168, '30d': 720, '90d': 2160 }
  const hours = rangeToHours[timeRange] || 168

  const { data: health } = useQuery({
    queryKey: ['analytics-health'],
    queryFn: () => api.get('/analytics/health-score'),
    refetchInterval: 60000,
  })

  const { data: responseTimes } = useQuery({
    queryKey: ['analytics-response', timeRange],
    queryFn: () => api.get(`/analytics/response-times?hours=${hours}`),
  })

  const { data: timeline = [] } = useQuery({
    queryKey: ['analytics-timeline', timeRange],
    queryFn: () => api.get(`/analytics/timeline?hours=${hours}`),
  })

  const { data: volunteerDeploy } = useQuery({
    queryKey: ['analytics-volunteer', timeRange],
    queryFn: () => api.get('/analytics/volunteer-deployment'),
  })

  const { data: resourceCoverage = [] } = useQuery({
    queryKey: ['analytics-resource', timeRange],
    queryFn: () => api.get('/analytics/resource-coverage'),
  })

  const { data: areaBreakdown = [] } = useQuery({
    queryKey: ['analytics-area', timeRange],
    queryFn: () => api.get(`/analytics/area-breakdown?hours=${hours}`),
  })

  // Backend returns score as 'green'/'amber'/'red' string
  const healthLabel = health?.score || 'green'
  const healthScore = healthLabel === 'green' ? 92 : healthLabel === 'amber' ? 65 : 30
  const healthColor = healthLabel === 'green' ? 'text-green-600' : healthLabel === 'amber' ? 'text-amber-600' : 'text-red-600'
  const healthBg = healthLabel === 'green' ? 'bg-green-50 dark:bg-green-900/20' : healthLabel === 'amber' ? 'bg-amber-50 dark:bg-amber-900/20' : 'bg-red-50 dark:bg-red-900/20'

  const downloadPDF = useCallback(async () => {
    if (!reportRef.current) return
    const canvas = await html2canvas(reportRef.current, { scale: 2, useCORS: true, backgroundColor: '#ffffff' })
    const imgData = canvas.toDataURL('image/png')
    const pdf = new jsPDF('l', 'mm', 'a4')
    const w = pdf.internal.pageSize.getWidth()
    const h = (canvas.height * w) / canvas.width
    pdf.addImage(imgData, 'PNG', 0, 0, w, h)
    pdf.save(`analytics-${new Date().toISOString().slice(0, 10)}.pdf`)
  }, [])

  return (
    <div className="h-full overflow-y-auto">
      <div ref={reportRef} className="p-4 space-y-4">
        {/* Header */}
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-bold">Analytics Dashboard</h1>
          <div className="flex items-center gap-2">
            <div className="flex gap-1 border border-gray-200 dark:border-gray-600 rounded-lg overflow-hidden">
              {['24h', '7d', '30d', '90d'].map((r) => (
                <button key={r} onClick={() => setTimeRange(r)} className={`px-3 py-1 text-xs font-medium ${timeRange === r ? 'bg-teal-100 dark:bg-teal-900/40 text-teal-700' : 'text-gray-500 hover:bg-gray-50 dark:hover:bg-gray-700'}`}>{r}</button>
              ))}
            </div>
            <button onClick={downloadPDF} className="flex items-center gap-1.5 px-3 py-1.5 border border-gray-300 dark:border-gray-600 text-xs rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"><Download className="w-3 h-3" />PDF</button>
          </div>
        </div>

        {/* Health Score + KPIs */}
        <div className="grid grid-cols-5 gap-4">
          <div className={`col-span-1 rounded-xl border border-gray-200 dark:border-gray-700 p-4 flex flex-col items-center justify-center ${healthBg}`}>
            <Shield className={`w-8 h-8 mb-2 ${healthColor}`} />
            <p className={`text-3xl font-black ${healthColor}`}>{healthScore}</p>
            <p className="text-xs text-gray-500 mt-1">Health Score</p>
          </div>
          <div className="col-span-4 grid grid-cols-4 gap-4">
            {[
              { label: 'Avg Response', value: responseTimes?.avg_seconds ? `${Math.round(responseTimes.avg_seconds / 60)}m` : '—', icon: Clock, color: 'text-blue-600', bg: 'bg-blue-50 dark:bg-blue-900/20' },
              { label: 'Sample Size', value: responseTimes?.sample_size ?? '—', icon: TrendingUp, color: 'text-green-600', bg: 'bg-green-50 dark:bg-green-900/20' },
              { label: 'Active Responders', value: volunteerDeploy?.total_online ?? '—', icon: Users, color: 'text-purple-600', bg: 'bg-purple-50 dark:bg-purple-900/20' },
              { label: 'On Task', value: volunteerDeploy?.on_task ?? '—', icon: Package, color: 'text-teal-600', bg: 'bg-teal-50 dark:bg-teal-900/20' },
            ].map((k) => (
              <div key={k.label} className={`rounded-xl border border-gray-200 dark:border-gray-700 p-4 ${k.bg}`}>
                <k.icon className={`w-5 h-5 mb-2 ${k.color}`} />
                <p className="text-2xl font-bold">{k.value}</p>
                <p className="text-[10px] text-gray-500 mt-1">{k.label}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Charts row 1 */}
        <div className="grid grid-cols-2 gap-4">
          {/* Incident Timeline */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
            <h3 className="text-sm font-semibold mb-3">Incident Volume</h3>
            <ResponsiveContainer width="100%" height={250}>
              <AreaChart data={timeline}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis dataKey="hour" tick={{ fontSize: 10 }} tickFormatter={(v) => v ? new Date(v).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : ''} />
                <YAxis tick={{ fontSize: 10 }} />
                <Tooltip labelFormatter={(v) => v ? new Date(v).toLocaleString() : ''} />
                <Area type="monotone" dataKey="total" stroke="#14b8a6" fill="#14b8a680" name="Total" />
                <Area type="monotone" dataKey="resolved" stroke="#22c55e" fill="#22c55e40" name="Resolved" />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          {/* Response Times - single aggregate, show as stat cards */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
            <h3 className="text-sm font-semibold mb-3">Response Times</h3>
            {responseTimes ? (
              <div className="grid grid-cols-2 gap-4 mt-6">
                <div className="text-center">
                  <p className="text-3xl font-black text-teal-600">{responseTimes.avg_seconds ? `${Math.round(responseTimes.avg_seconds / 60)}` : '—'}</p>
                  <p className="text-xs text-gray-500 mt-1">Avg (min)</p>
                </div>
                <div className="text-center">
                  <p className="text-3xl font-black text-amber-600">{responseTimes.p50 ? `${Math.round(responseTimes.p50 / 60)}` : '—'}</p>
                  <p className="text-xs text-gray-500 mt-1">Median (min)</p>
                </div>
                <div className="text-center">
                  <p className="text-3xl font-black text-orange-600">{responseTimes.p90 ? `${Math.round(responseTimes.p90 / 60)}` : '—'}</p>
                  <p className="text-xs text-gray-500 mt-1">P90 (min)</p>
                </div>
                <div className="text-center">
                  <p className="text-3xl font-black text-gray-600">{responseTimes.sample_size ?? '—'}</p>
                  <p className="text-xs text-gray-500 mt-1">Sample Size</p>
                </div>
              </div>
            ) : <p className="text-sm text-gray-400 text-center mt-8">No data yet</p>}
          </div>
        </div>

        {/* Charts row 2 */}
        <div className="grid grid-cols-3 gap-4">
          {/* Area breakdown */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
            <h3 className="text-sm font-semibold mb-3">By Area</h3>
            <ResponsiveContainer width="100%" height={250}>
              <PieChart>
                <Pie data={areaBreakdown} dataKey="incident_count" nameKey="area_id" cx="50%" cy="50%" outerRadius={80} label={({ name, percent }) => `${name || 'Unknown'} ${(percent * 100).toFixed(0)}%`}>
                  {areaBreakdown.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>

          {/* Volunteer Deployment - single aggregate, show as gauge-like */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
            <h3 className="text-sm font-semibold mb-3">Volunteer Status</h3>
            {volunteerDeploy ? (
              <div className="space-y-4 mt-4">
                {[
                  { label: 'Online', value: volunteerDeploy.total_online, color: 'bg-blue-500' },
                  { label: 'Available', value: volunteerDeploy.available, color: 'bg-green-500' },
                  { label: 'On Task', value: volunteerDeploy.on_task, color: 'bg-orange-500' },
                ].map((s) => (
                  <div key={s.label} className="flex items-center gap-3">
                    <div className={`w-3 h-3 rounded-full ${s.color}`} />
                    <span className="text-sm flex-1">{s.label}</span>
                    <span className="text-lg font-bold">{s.value ?? 0}</span>
                  </div>
                ))}
              </div>
            ) : <p className="text-sm text-gray-400 text-center mt-8">No data</p>}
          </div>

          {/* Resource Coverage */}
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
            <h3 className="text-sm font-semibold mb-3">Resource Coverage</h3>
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={resourceCoverage} layout="vertical">
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis type="number" tick={{ fontSize: 10 }} />
                <YAxis dataKey="type" type="category" tick={{ fontSize: 10 }} width={60} />
                <Tooltip />
                <Bar dataKey="available" fill="#14b8a6" name="Available" radius={[0, 2, 2, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>
    </div>
  )
}
