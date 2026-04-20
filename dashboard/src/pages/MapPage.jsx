import { useEffect, useRef, useState } from 'react'
import { useAuthStore } from '../stores/authStore'
import { useQuery } from '@tanstack/react-query'
import { api } from '../api/client'
import { useSocketStore } from '../stores/socketStore'
import { usePreferencesStore } from '../stores/preferencesStore'
import { Layers, X, Eye, EyeOff } from 'lucide-react'
import mapboxgl from 'mapbox-gl'

const MAPBOX_TOKEN = (import.meta.env.VITE_MAPBOX_TOKEN || '').trim()
mapboxgl.accessToken = MAPBOX_TOKEN

const OSM_STYLE = {
  version: 8,
  sources: {
    osm: {
      type: 'raster',
      tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      tileSize: 256,
      maxzoom: 19,
      attribution: '© OpenStreetMap contributors',
    },
  },
  layers: [{ id: 'osm', type: 'raster', source: 'osm' }],
}

const CARTO_STYLE = {
  version: 8,
  sources: {
    carto: {
      type: 'raster',
      tiles: [
        'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        'https://b.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        'https://c.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      ],
      tileSize: 256,
      maxzoom: 20,
      attribution: '© OpenStreetMap © CARTO',
    },
  },
  layers: [{ id: 'carto', type: 'raster', source: 'carto' }],
}

const ESRI_STYLE = {
  version: 8,
  sources: {
    esri: {
      type: 'raster',
      tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}'],
      tileSize: 256,
      maxzoom: 19,
      attribution: 'Tiles © Esri',
    },
  },
  layers: [{ id: 'esri', type: 'raster', source: 'esri' }],
}

const BASEMAP_PROVIDERS = [
  ...(MAPBOX_TOKEN ? [{ key: 'mapbox', label: 'Mapbox', style: 'mapbox' }] : []),
  { key: 'osm', label: 'OpenStreetMap', style: OSM_STYLE },
  { key: 'carto', label: 'CARTO', style: CARTO_STYLE },
  { key: 'esri', label: 'Esri', style: ESRI_STYLE },
]

const MAPBOX_STYLE_OPTIONS = [
  { id: 'streets-v12', label: 'streets' },
  { id: 'outdoors-v12', label: 'outdoors' },
  { id: 'satellite-streets-v12', label: 'satellite' },
]

const LEGACY_STYLE_MAP = {
  'dark-v11': 'streets-v12',
  'light-v11': 'streets-v12',
}

const MAPBOX_STYLE_IDS = new Set(MAPBOX_STYLE_OPTIONS.map((s) => s.id))

function normalizeMapboxStyle(style) {
  const mapped = LEGACY_STYLE_MAP[style] || style
  return MAPBOX_STYLE_IDS.has(mapped) ? mapped : 'streets-v12'
}

const SEVERITY_COLORS = ['#22c55e', '#eab308', '#f97316', '#ef4444', '#991b1b']
const STATUS_COLORS = { active: '#ef4444', 'in-progress': '#f97316', assigned: '#eab308', resolved: '#22c55e', submitted: '#9ca3af' }

export default function MapPage() {
  const user = useAuthStore((s) => s.user)
  const [activeParish, setActiveParish] = useState(null)
  const [mapTokenIssue, setMapTokenIssue] = useState(!MAPBOX_TOKEN)
  const [activeBasemapLabel, setActiveBasemapLabel] = useState(MAPBOX_TOKEN ? 'Mapbox' : BASEMAP_PROVIDERS[0].label)
  const [mapDiagnostics, setMapDiagnostics] = useState({
    provider: MAPBOX_TOKEN ? 'Mapbox' : BASEMAP_PROVIDERS[0].label,
    lastError: '',
    tileUrl: '',
  })
  const mapContainer = useRef(null)
  const mapRef = useRef(null)
  const incidentsRef = useRef([])
  const volunteersRef = useRef([])
  const resourcesRef = useRef([])
  const [mapLoaded, setMapLoaded] = useState(false)
  const [showLayers, setShowLayers] = useState(false)
  const [sidePanel, setSidePanel] = useState(null)
  const socket = useSocketStore((s) => s.socket)
  const { layerVisibility, setLayerVisibility, mapStyle, setMapStyle } = usePreferencesStore()
  const normalizedMapStyle = normalizeMapboxStyle(mapStyle)

  const { data: incidents = [] } = useQuery({
    queryKey: ['incidents'],
    queryFn: () => api.get('/incidents'),
    refetchInterval: 30000,
  })

  const { data: volunteers = [] } = useQuery({
    queryKey: ['volunteers'],
    queryFn: () => api.get('/volunteers/list'),
    refetchInterval: 30000,
  })

  const { data: resources = [] } = useQuery({
    queryKey: ['resources'],
    queryFn: () => api.get('/resources'),
    refetchInterval: 60000,
  })

  useEffect(() => {
    incidentsRef.current = incidents
  }, [incidents])

  useEffect(() => {
    volunteersRef.current = volunteers
  }, [volunteers])

  useEffect(() => {
    resourcesRef.current = resources
  }, [resources])

  useEffect(() => {
    if (mapStyle !== normalizedMapStyle) setMapStyle(normalizedMapStyle)
  }, [mapStyle, normalizedMapStyle, setMapStyle])

  // Determine active parish for volunteer/coordinator
  useEffect(() => {
    if (!user || (user.role !== 'volunteer' && user.role !== 'coordinator')) {
      setActiveParish(null)
      return
    }
    // Find user's parish by matching their last_lat/last_lon to a parish center (approximate)
    // Or, if user has areaId/parish property, use that
    // For demo, use volunteers list if user is volunteer
    let lat = user.last_lat
    let lon = user.last_lon
    if (!lat || !lon) {
      // Try to find in volunteers list
      const v = volunteers.find((vol) => vol.id === user.id)
      if (v) {
        lat = v.last_lat
        lon = v.last_lon
      }
    }
    if (lat && lon) {
      // Find closest parish
      const parishList = [
        { name: 'Kingston', lat: 17.9712, lon: -76.7936 },
        { name: 'Saint Andrew', lat: 18.08, lon: -76.78 },
        { name: 'Saint Thomas', lat: 17.92, lon: -76.35 },
        { name: 'Portland', lat: 18.15, lon: -76.42 },
        { name: 'Saint Mary', lat: 18.37, lon: -76.9 },
        { name: 'Saint Ann', lat: 18.43, lon: -77.2 },
        { name: 'Trelawny', lat: 18.35, lon: -77.65 },
        { name: 'Saint James', lat: 18.47, lon: -77.92 },
        { name: 'Hanover', lat: 18.4, lon: -78.13 },
        { name: 'Westmoreland', lat: 18.22, lon: -78.1 },
        { name: 'Saint Elizabeth', lat: 18.05, lon: -77.7 },
        { name: 'Manchester', lat: 18.05, lon: -77.5 },
        { name: 'Clarendon', lat: 17.95, lon: -77.2 },
        { name: 'Saint Catherine', lat: 18.05, lon: -77.05 },
      ]
      let minDist = Infinity
      let closest = null
      for (const p of parishList) {
        const d = Math.sqrt(Math.pow(p.lat - lat, 2) + Math.pow(p.lon - lon, 2))
        if (d < minDist) {
          minDist = d
          closest = p
        }
      }
      setActiveParish(closest ? closest.name : null)
    } else {
      setActiveParish(null)
    }
  }, [user, volunteers])

  const toFiniteNumber = (value) => {
    const n = Number(value)
    return Number.isFinite(n) ? n : null
  }

  const pushIncidentData = (map, rows) => {
    const src = map.getSource('incidents')
    if (!src) return

    const features = rows
      .map((i) => {
        const lon = toFiniteNumber(i.lon)
        const lat = toFiniteNumber(i.lat)
        if (lon == null || lat == null) return null
        return {
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [lon, lat] },
          properties: {
            id: i.id,
            type: i.type,
            severity: i.severity,
            status: i.status,
            description: i.description,
            areaId: i.areaId,
            assignedTo: i.assignedTo,
            responderName: i.responderName,
          },
        }
      })
      .filter(Boolean)

    src.setData({ type: 'FeatureCollection', features })
  }

  const pushVolunteerData = (map, rows) => {
    const src = map.getSource('volunteers')
    if (!src) return

    const features = rows
      .map((v) => {
        const lon = toFiniteNumber(v.last_lon)
        const lat = toFiniteNumber(v.last_lat)
        if (lon == null || lat == null) return null
        return {
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [lon, lat] },
          properties: {
            id: v.id,
            username: v.username,
            role: v.role,
            availability: v.availability,
            skills: JSON.stringify(v.skills || []),
            active_tasks: v.active_tasks,
          },
        }
      })
      .filter(Boolean)

    src.setData({ type: 'FeatureCollection', features })
  }

  const pushResourceData = (map, rows) => {
    const src = map.getSource('resources')
    if (!src) return

    const features = rows.filter((r) => r.location).map((r) => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [0, 0] },
      properties: { id: r.id, type: r.type, quantity: r.quantity },
    }))

    src.setData({ type: 'FeatureCollection', features })
  }

  // Initialize map
  useEffect(() => {
    if (mapRef.current || !mapContainer.current) return
    let providerIndex = 0
    let initialStyleReady = false
    let styleStartupTimer = null
    let lastFailoverAt = 0

    const getProvider = () => BASEMAP_PROVIDERS[providerIndex]
    const resolveProviderStyle = (provider) => {
      if (provider.style === 'mapbox') return `mapbox://styles/mapbox/${normalizedMapStyle}`
      return provider.style
    }

    const map = new mapboxgl.Map({
      container: mapContainer.current,
      style: resolveProviderStyle(getProvider()),
      center: [-77.3, 18.1],
      zoom: 9,
    })

    const setProviderState = () => {
      const provider = getProvider()
      setActiveBasemapLabel(provider.label)
      setMapTokenIssue(provider.key !== 'mapbox')
      setMapDiagnostics((prev) => ({ ...prev, provider: provider.label }))
    }

    const armStartupTimer = () => {
      clearTimeout(styleStartupTimer)
      styleStartupTimer = setTimeout(() => {
        if (!initialStyleReady) switchToNextProvider('style startup timeout')
      }, 5500)
    }

    const switchToNextProvider = (reason, tileUrl = '') => {
      if (providerIndex >= BASEMAP_PROVIDERS.length - 1) {
        setMapDiagnostics((prev) => ({
          ...prev,
          provider: getProvider().label,
          lastError: reason,
          tileUrl: tileUrl || prev.tileUrl,
        }))
        return false
      }

      providerIndex += 1
      lastFailoverAt = Date.now()
      initialStyleReady = false

      const next = getProvider()
      setActiveBasemapLabel(next.label)
      setMapTokenIssue(next.key !== 'mapbox')
      setMapDiagnostics((prev) => ({
        ...prev,
        provider: next.label,
        lastError: reason,
        tileUrl: tileUrl || prev.tileUrl,
      }))

      map.setStyle(resolveProviderStyle(next))
      armStartupTimer()
      return true
    }

    const onIncidentClick = (e) => {
      const props = e.features?.[0]?.properties || {}
      setSidePanel({ type: 'incident', data: { ...props, lat: e.lngLat.lat, lon: e.lngLat.lng } })
    }

    const onVolunteerClick = (e) => {
      const props = e.features?.[0]?.properties || {}
      setSidePanel({ type: 'volunteer', data: { ...props, lat: e.lngLat.lat, lon: e.lngLat.lng } })
    }

    const onClusterClick = (e) => {
      const features = map.queryRenderedFeatures(e.point, { layers: ['incident-clusters'] })
      if (!features.length) return

      const clusterId = features[0].properties.cluster_id
      const source = map.getSource('incidents')
      if (!source || !source.getClusterExpansionZoom) return

      source.getClusterExpansionZoom(clusterId, (err, zoom) => {
        if (!err) map.easeTo({ center: features[0].geometry.coordinates, zoom })
      })
    }

    const setPointer = () => {
      map.getCanvas().style.cursor = 'pointer'
    }

    const clearPointer = () => {
      map.getCanvas().style.cursor = ''
    }

    const ensureOperationalLayers = () => {
      if (!map.getSource('incidents')) {
        map.addSource('incidents', { type: 'geojson', data: { type: 'FeatureCollection', features: [] }, cluster: true, clusterMaxZoom: 14, clusterRadius: 50 })
      }
      if (!map.getLayer('incident-clusters')) {
        map.addLayer({ id: 'incident-clusters', type: 'circle', source: 'incidents', filter: ['has', 'point_count'], paint: { 'circle-color': ['step', ['get', 'point_count'], '#51bbd6', 10, '#f1f075', 30, '#f28cb1'], 'circle-radius': ['step', ['get', 'point_count'], 18, 10, 24, 30, 32] } })
      }
      if (!map.getLayer('incident-cluster-count')) {
        map.addLayer({ id: 'incident-cluster-count', type: 'symbol', source: 'incidents', filter: ['has', 'point_count'], layout: { 'text-field': '{point_count_abbreviated}', 'text-size': 12 } })
      }
      if (!map.getLayer('incident-points')) {
        map.addLayer({ id: 'incident-points', type: 'circle', source: 'incidents', filter: ['!', ['has', 'point_count']], paint: { 'circle-color': ['match', ['get', 'status'], 'active', '#ef4444', 'in-progress', '#f97316', 'resolved', '#22c55e', '#9ca3af'], 'circle-radius': ['interpolate', ['linear'], ['get', 'severity'], 1, 6, 5, 14], 'circle-stroke-width': 2, 'circle-stroke-color': '#fff' } })
      }
      if (!map.getLayer('incident-pulse')) {
        map.addLayer({ id: 'incident-pulse', type: 'circle', source: 'incidents', filter: ['all', ['!', ['has', 'point_count']], ['==', ['get', 'assignedTo'], null], ['==', ['get', 'status'], 'active']], paint: { 'circle-color': '#ef4444', 'circle-radius': ['interpolate', ['linear'], ['get', 'severity'], 1, 10, 5, 22], 'circle-opacity': 0.3 } })
      }

      if (!map.getSource('volunteers')) {
        map.addSource('volunteers', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      }
      if (!map.getLayer('volunteer-points')) {
        map.addLayer({ id: 'volunteer-points', type: 'circle', source: 'volunteers', paint: { 'circle-color': ['match', ['get', 'availability'], 'available', '#3b82f6', 'on_task', '#6366f1', '#9ca3af'], 'circle-radius': ['match', ['get', 'availability'], 'available', 7, 'on_task', 6, 5], 'circle-stroke-width': 2, 'circle-stroke-color': '#fff' } })
      }

      if (!map.getSource('resources')) {
        map.addSource('resources', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      }
      if (!map.getLayer('resource-points')) {
        map.addLayer({ id: 'resource-points', type: 'circle', source: 'resources', paint: { 'circle-color': '#eab308', 'circle-radius': 6, 'circle-stroke-width': 2, 'circle-stroke-color': '#fff' }, layout: { visibility: 'none' } })
      }

      if (!map.getLayer('incident-heatmap')) {
        map.addLayer({
          id: 'incident-heatmap', type: 'heatmap', source: 'incidents',
          maxzoom: 14,
          paint: {
            'heatmap-weight': ['interpolate', ['linear'], ['get', 'severity'], 1, 0.3, 5, 1],
            'heatmap-intensity': ['interpolate', ['linear'], ['zoom'], 0, 1, 14, 3],
            'heatmap-radius': ['interpolate', ['linear'], ['zoom'], 0, 15, 14, 30],
            'heatmap-color': ['interpolate', ['linear'], ['heatmap-density'], 0, 'rgba(0,0,0,0)', 0.2, '#2196f3', 0.4, '#4caf50', 0.6, '#ffeb3b', 0.8, '#ff9800', 1, '#f44336'],
            'heatmap-opacity': 0.6,
          },
          layout: { visibility: 'none' },
        })
      }

      if (!map.getLayer('volunteer-coverage')) {
        map.addLayer({
          id: 'volunteer-coverage', type: 'circle', source: 'volunteers',
          paint: {
            'circle-color': '#3b82f6',
            'circle-radius': ['interpolate', ['linear'], ['zoom'], 8, 10, 14, 80],
            'circle-opacity': 0.08,
            'circle-stroke-width': 1,
            'circle-stroke-color': '#3b82f6',
            'circle-stroke-opacity': 0.2,
          },
          layout: { visibility: 'none' },
        })
      }

      map.off('click', 'incident-points', onIncidentClick)
      map.on('click', 'incident-points', onIncidentClick)
      map.off('click', 'volunteer-points', onVolunteerClick)
      map.on('click', 'volunteer-points', onVolunteerClick)
      map.off('click', 'incident-clusters', onClusterClick)
      map.on('click', 'incident-clusters', onClusterClick)

      map.off('mouseenter', 'incident-points', setPointer)
      map.on('mouseenter', 'incident-points', setPointer)
      map.off('mouseleave', 'incident-points', clearPointer)
      map.on('mouseleave', 'incident-points', clearPointer)
      map.off('mouseenter', 'volunteer-points', setPointer)
      map.on('mouseenter', 'volunteer-points', setPointer)
      map.off('mouseleave', 'volunteer-points', clearPointer)
      map.on('mouseleave', 'volunteer-points', clearPointer)
    }

    map.addControl(new mapboxgl.NavigationControl(), 'top-right')
    setProviderState()
    armStartupTimer()

    map.on('style.load', () => {
      initialStyleReady = true
      clearTimeout(styleStartupTimer)
      setProviderState()
      ensureOperationalLayers()
      pushIncidentData(map, incidentsRef.current)
      pushVolunteerData(map, volunteersRef.current)
      pushResourceData(map, resourcesRef.current)
      setMapLoaded(true)
    })

    map.on('error', (event) => {
      const message = String(event?.error?.message || 'Map rendering error')
      const lower = message.toLowerCase()
      const sourceId = String(event?.sourceId || event?.source?.id || '').toLowerCase()
      const tileUrl = event?.tile?.request?.url || event?.source?.tiles?.[0] || event?.source?.url || ''
      const activeProvider = getProvider()

      setMapDiagnostics((prev) => ({
        ...prev,
        provider: getProvider().label,
        lastError: message,
        tileUrl: tileUrl || prev.tileUrl,
      }))

      const networkFailure =
        lower.includes('failed to fetch') ||
        lower.includes('request failed') ||
        lower.includes('forbidden') ||
        lower.includes('unauthorized') ||
        lower.includes('access token') ||
        lower.includes('401') ||
        lower.includes('403') ||
        lower.includes('sprite') ||
        lower.includes('glyph') ||
        lower.includes('tile')

      const mapboxAuthFailure =
        activeProvider.key === 'mapbox' &&
        (lower.includes('401') || lower.includes('403') || lower.includes('access token') || lower.includes('unauthorized') || lower.includes('forbidden') || String(tileUrl).includes('api.mapbox.com'))

      const mapboxCompositeFailure =
        activeProvider.key === 'mapbox' &&
        (sourceId.includes('composite') || String(tileUrl).startsWith('mapbox://') || String(tileUrl).includes('mapbox.mapbox-'))

      const basemapSourceFailure =
        sourceId.includes('composite') ||
        sourceId.includes('mapbox') ||
        sourceId.includes('osm') ||
        sourceId.includes('carto') ||
        sourceId.includes('esri')

      const shouldFailover =
        mapboxAuthFailure ||
        mapboxCompositeFailure ||
        (networkFailure && (!initialStyleReady || basemapSourceFailure || activeProvider.key === 'mapbox'))
      const failoverCooldownElapsed = Date.now() - lastFailoverAt > 1000

      if (shouldFailover && failoverCooldownElapsed) {
        switchToNextProvider(message, tileUrl)
      }
    })

    mapRef.current = map
    return () => {
      clearTimeout(styleStartupTimer)
      map.remove()
      mapRef.current = null
    }
  }, [])

  // Update incident data
  useEffect(() => {
    if (!mapLoaded || !mapRef.current) return
    pushIncidentData(mapRef.current, incidents)
  }, [incidents, mapLoaded])

  // Update volunteer data
  useEffect(() => {
    if (!mapLoaded || !mapRef.current) return
    pushVolunteerData(mapRef.current, volunteers)
  }, [volunteers, mapLoaded])

  // Update resource data
  useEffect(() => {
    if (!mapLoaded || !mapRef.current) return
    pushResourceData(mapRef.current, resources)
  }, [resources, mapLoaded])

  // Socket.io real-time updates
  useEffect(() => {
    if (!socket) return
    const handleIncidentCreated = () => {} // TanStack Query will refetch
    const handleIncidentUpdated = () => {}
    const handleUserLocation = (data) => {
      if (!mapLoaded || !mapRef.current) return
      // Update volunteer position in source
    }
    socket.on('incident:created', handleIncidentCreated)
    socket.on('incident:updated', handleIncidentUpdated)
    socket.on('user:location', handleUserLocation)
    return () => {
      socket.off('incident:created', handleIncidentCreated)
      socket.off('incident:updated', handleIncidentUpdated)
      socket.off('user:location', handleUserLocation)
    }
  }, [socket, mapLoaded])

  // Layer visibility toggle
  const toggleLayer = (key, layerIds) => {
    const next = !layerVisibility[key]
    setLayerVisibility(key, next)
    if (mapRef.current && mapLoaded) {
      layerIds.forEach((lid) => {
        if (mapRef.current.getLayer(lid)) {
          mapRef.current.setLayoutProperty(lid, 'visibility', next ? 'visible' : 'none')
        }
      })
    }
  }

  const layerConfig = [
    { key: 'incidents', label: 'Incidents', layers: ['incident-points', 'incident-clusters', 'incident-cluster-count', 'incident-pulse'] },
    { key: 'volunteers', label: 'Volunteers', layers: ['volunteer-points'] },
    { key: 'resources', label: 'Resources', layers: ['resource-points'] },
    { key: 'heatmap', label: 'Heatmap', layers: ['incident-heatmap'] },
    { key: 'coverage', label: 'Coverage', layers: ['volunteer-coverage'] },
  ]

  return (
    <div className="relative h-full">
      {mapTokenIssue && (
        <div className="absolute top-14 left-1/2 -translate-x-1/2 z-20 bg-amber-100 text-amber-800 border border-amber-200 px-3 py-1.5 rounded-lg text-xs shadow">
          Mapbox unavailable. Using {activeBasemapLabel} basemap.
        </div>
      )}

      {/* Active Location Indicator */}
      {user && (user.role === 'volunteer' || user.role === 'coordinator') && activeParish && (
        <div className="absolute top-3 left-1/2 -translate-x-1/2 z-20 bg-white dark:bg-gray-800 px-4 py-2 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 text-sm font-medium text-gray-700 dark:text-gray-200 flex items-center gap-2">
          <span className="inline-block w-2 h-2 rounded-full bg-green-500 mr-2"></span>
          Active Location: <span className="ml-1 font-semibold">{activeParish} parish</span>
        </div>
      )}
      <div ref={mapContainer} className="w-full h-full" />

      {/* Layer control */}
      <div className="absolute top-3 left-3 z-10">
        <button
          onClick={() => setShowLayers(!showLayers)}
          className="bg-white dark:bg-gray-800 p-2.5 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700"
        >
          <Layers className="w-4 h-4" />
        </button>

        {showLayers && (
          <div className="mt-2 bg-white dark:bg-gray-800 rounded-lg shadow-xl border border-gray-200 dark:border-gray-700 p-3 w-48">
            <h3 className="text-xs font-semibold text-gray-500 uppercase mb-2">Layers</h3>
            {layerConfig.map(({ key, label, layers }) => (
              <button
                key={key}
                onClick={() => toggleLayer(key, layers)}
                className="flex items-center gap-2 w-full text-left py-1.5 text-sm hover:text-teal-600"
              >
                {layerVisibility[key] ? <Eye className="w-3.5 h-3.5 text-teal-500" /> : <EyeOff className="w-3.5 h-3.5 text-gray-400" />}
                {label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Style switcher */}
      <div className="absolute top-3 right-14 z-10 flex gap-1 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 p-1">
        {MAPBOX_STYLE_OPTIONS.map((styleOpt) => (
          <button
            key={styleOpt.id}
            disabled={mapTokenIssue}
            onClick={() => {
              if (!mapRef.current || mapTokenIssue) return
              setMapStyle(styleOpt.id)
              mapRef.current.setStyle(`mapbox://styles/mapbox/${styleOpt.id}`)
            }}
            className={`px-2 py-1 text-[10px] rounded font-medium ${normalizedMapStyle === styleOpt.id ? 'bg-teal-100 dark:bg-teal-900/40 text-teal-700' : 'text-gray-500 hover:text-gray-700'} ${mapTokenIssue ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            {styleOpt.label}
          </button>
        ))}
      </div>

      {(mapDiagnostics.lastError || mapTokenIssue) && (
        <div className="absolute bottom-3 left-3 z-20 max-w-sm bg-black/75 text-white rounded-lg px-3 py-2 text-[11px] leading-snug shadow-lg">
          <p className="font-semibold">Basemap: {mapDiagnostics.provider || activeBasemapLabel}</p>
          {mapDiagnostics.lastError && <p className="mt-1 break-words">{mapDiagnostics.lastError}</p>}
          {mapDiagnostics.tileUrl && <p className="mt-1 break-all text-gray-200">{mapDiagnostics.tileUrl}</p>}
        </div>
      )}

      {/* Side panel */}
      {sidePanel && (
        <div className="absolute right-0 top-0 h-full w-96 bg-white dark:bg-gray-800 shadow-2xl border-l border-gray-200 dark:border-gray-700 z-20 overflow-y-auto">
          <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
            <h3 className="font-semibold text-sm capitalize">{sidePanel.type} Details</h3>
            <button onClick={() => setSidePanel(null)} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
              <X className="w-4 h-4" />
            </button>
          </div>
          <div className="p-4 space-y-3">
            {sidePanel.type === 'incident' && (
              <>
                <div className="flex items-center gap-2">
                  <span className={`w-3 h-3 rounded-full ${STATUS_COLORS[sidePanel.data.status] ? '' : ''}`} style={{ backgroundColor: STATUS_COLORS[sidePanel.data.status] }} />
                  <span className="text-sm font-medium capitalize">{sidePanel.data.type}</span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-gray-100 dark:bg-gray-700">Sev {sidePanel.data.severity}</span>
                </div>
                <p className="text-sm text-gray-600 dark:text-gray-400">{sidePanel.data.description}</p>
                <p className="text-xs text-gray-500">Area: {sidePanel.data.areaId}</p>
                <p className="text-xs text-gray-500">Status: {sidePanel.data.status}</p>
                <p className="text-xs text-gray-500">Assigned: {sidePanel.data.responderName || 'Unassigned'}</p>
              </>
            )}
            {sidePanel.type === 'volunteer' && (
              <>
                <p className="text-sm font-medium">{sidePanel.data.username}</p>
                <p className="text-xs text-gray-500">Role: {sidePanel.data.role}</p>
                <p className="text-xs text-gray-500">Status: {sidePanel.data.availability}</p>
                <p className="text-xs text-gray-500">Active tasks: {sidePanel.data.active_tasks}</p>
              </>
            )}
          </div>
        </div>
      )}

    </div>
  )
}
