import { Routes, Route, Navigate } from 'react-router-dom'
import { useEffect } from 'react'
import { usePreferencesStore } from './stores/preferencesStore'
import Layout from './components/Layout'
import LoginPage from './pages/LoginPage'
import DashboardPage from './pages/DashboardPage'
import MapPage from './pages/MapPage'
import IncidentsPage from './pages/IncidentsPage'
import IncidentDetailPage from './pages/IncidentDetailPage'
import VolunteersPage from './pages/VolunteersPage'
import ResourcesPage from './pages/ResourcesPage'
import BroadcastsPage from './pages/BroadcastsPage'
import AnalyticsPage from './pages/AnalyticsPage'
import ReportsPage from './pages/ReportsPage'
import PublicStatusPage from './pages/PublicStatusPage'
import ProtectedRoute from './components/ProtectedRoute'

export default function App() {
  const darkMode = usePreferencesStore((s) => s.darkMode)

  useEffect(() => {
    document.documentElement.classList.toggle('dark', darkMode)
  }, [darkMode])

  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/public" element={<PublicStatusPage />} />
      <Route element={<ProtectedRoute><Layout /></ProtectedRoute>}>
        <Route path="/dashboard" element={<DashboardPage />} />
        <Route path="/map" element={<MapPage />} />
        <Route path="/incidents" element={<IncidentsPage />} />
        <Route path="/incidents/:id" element={<IncidentDetailPage />} />
        <Route path="/volunteers" element={<VolunteersPage />} />
        <Route path="/resources" element={<ResourcesPage />} />
        <Route path="/broadcasts" element={<BroadcastsPage />} />
        <Route path="/analytics" element={<AnalyticsPage />} />
        <Route path="/reports" element={<ReportsPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  )
}  
