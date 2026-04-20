import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export const usePreferencesStore = create(
  persist(
    (set) => ({
      darkMode: false,
      sidebarCollapsed: false,
      mapStyle: 'dark-v11',
      layerVisibility: { incidents: true, volunteers: true, resources: false, heatmap: false, coverage: false },
      incidentFilters: { statuses: [], types: [], timeRange: 'all', search: '' },
      selectedIncidentId: null,

      toggleDarkMode: () => set((s) => {
        const next = !s.darkMode
        document.documentElement.classList.toggle('dark', next)
        return { darkMode: next }
      }),
      toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
      setMapStyle: (mapStyle) => set({ mapStyle }),
      setLayerVisibility: (key, val) => set((s) => ({ layerVisibility: { ...s.layerVisibility, [key]: val } })),
      setIncidentFilters: (filters) => set((s) => ({ incidentFilters: { ...s.incidentFilters, ...filters } })),
      setSelectedIncidentId: (id) => set({ selectedIncidentId: id }),
    }),
    { name: 'prefs-storage' }
  )
)
