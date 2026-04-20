// seed.js
const { Pool } = require('pg');
require('dotenv').config();

const databaseUrl = process.env.DATABASE_URL;

// ============================================================
// Database bootstrap
// ============================================================

function quoteIdentifier(value) {
  return `"${String(value).replace(/"/g, '""')}"`;
}

async function ensureDatabaseExists() {
  if (!databaseUrl) throw new Error('DATABASE_URL is not set in .env');
  const parsedUrl = new URL(databaseUrl);
  const dbName = parsedUrl.pathname.replace(/^\//, '');
  if (!dbName) throw new Error('DATABASE_URL must include a database name');

  const maintenanceUrl = new URL(databaseUrl);
  maintenanceUrl.pathname = '/postgres';

  const adminPool = new Pool({ connectionString: maintenanceUrl.toString() });
  try {
    const { rowCount } = await adminPool.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [dbName]
    );
    if (rowCount === 0) {
      await adminPool.query(`CREATE DATABASE ${quoteIdentifier(dbName)}`);
      console.log(`Database created: ${dbName}`);
    }
  } finally {
    await adminPool.end();
  }
}

async function ensureSchema(client) {
  await client.query(`
    CREATE EXTENSION IF NOT EXISTS postgis;

    -- Users
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      phone VARCHAR(20) UNIQUE NOT NULL,
      role VARCHAR(20) NOT NULL,
      organisation_id INTEGER,
      skills JSONB,
      location GEOGRAPHY(POINT),
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- Incidents
    CREATE TABLE IF NOT EXISTS incidents (
      id SERIAL PRIMARY KEY,
      type VARCHAR(50) NOT NULL,
      location GEOGRAPHY(POINT) NOT NULL,
      severity INTEGER CHECK (severity BETWEEN 1 AND 5),
      description TEXT,
      disaster_type VARCHAR(50),
      area_id VARCHAR(100),
      status VARCHAR(20) DEFAULT 'active',
      submitted_by INTEGER REFERENCES users(id),
      assigned_to INTEGER REFERENCES users(id),
      idempotency_key VARCHAR(255) UNIQUE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_incidents_location ON incidents USING GIST(location);

    -- Resources
    CREATE TABLE IF NOT EXISTS resources (
      id SERIAL PRIMARY KEY,
      type VARCHAR(50) NOT NULL,
      quantity INTEGER NOT NULL,
      unit VARCHAR(20),
      location GEOGRAPHY(POINT),
      organisation_id INTEGER REFERENCES users(id),
      status VARCHAR(20) DEFAULT 'available',
      last_updated TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_resources_location ON resources USING GIST(location);

    -- Refresh tokens
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id),
      token TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL
    );

    -- Processed requests (idempotency)
    CREATE TABLE IF NOT EXISTS processed_requests (
      idempotency_key VARCHAR(255) PRIMARY KEY,
      response JSONB,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- OTPs
    CREATE TABLE IF NOT EXISTS otps (
      phone VARCHAR(20) PRIMARY KEY,
      code VARCHAR(6) NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL
    );

    -- Resource allocations
    CREATE TABLE IF NOT EXISTS resource_allocations (
      id SERIAL PRIMARY KEY,
      resource_id INTEGER REFERENCES resources(id),
      incident_id INTEGER REFERENCES incidents(id),
      quantity INTEGER NOT NULL,
      allocated_at TIMESTAMPTZ DEFAULT NOW(),
      notes TEXT
    );

    -- Notifications
    CREATE TABLE IF NOT EXISTS notifications (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id),
      type VARCHAR(50) NOT NULL,
      data JSONB,
      read BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- Incident history
    CREATE TABLE IF NOT EXISTS incident_history (
      id SERIAL PRIMARY KEY,
      incident_id INTEGER REFERENCES incidents(id),
      from_status VARCHAR(20),
      to_status VARCHAR(20),
      changed_by INTEGER REFERENCES users(id),
      changed_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- Broadcast alerts
    CREATE TABLE IF NOT EXISTS broadcast_alerts (
      id SERIAL PRIMARY KEY,
      message TEXT NOT NULL,
      target_roles VARCHAR(50) DEFAULT 'all',
      expires_at TIMESTAMPTZ,
      created_by INTEGER REFERENCES users(id),
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- User alert acknowledgements
    CREATE TABLE IF NOT EXISTS user_alerts (
      user_id INTEGER REFERENCES users(id),
      alert_id INTEGER REFERENCES broadcast_alerts(id),
      acknowledged BOOLEAN DEFAULT FALSE,
      acknowledged_at TIMESTAMPTZ,
      delivered_via VARCHAR(20) DEFAULT 'push',
      PRIMARY KEY (user_id, alert_id)
    );

    -- Volunteer stats / gamification
    CREATE TABLE IF NOT EXISTS volunteer_stats (
      user_id INTEGER PRIMARY KEY REFERENCES users(id),
      tasks_completed INTEGER DEFAULT 0,
      hours_contributed NUMERIC(10,2) DEFAULT 0,
      badges JSONB DEFAULT '[]',
      streak_days INTEGER DEFAULT 0,
      last_active_at TIMESTAMPTZ,
      leaderboard_opt_in BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- Messages (two-way chat per incident)
    CREATE TABLE IF NOT EXISTS messages (
      id SERIAL PRIMARY KEY,
      incident_id INTEGER REFERENCES incidents(id) ON DELETE CASCADE,
      sender_id INTEGER REFERENCES users(id),
      content TEXT NOT NULL,
      message_type VARCHAR(20) DEFAULT 'text',
      delivered BOOLEAN DEFAULT FALSE,
      read BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- Device tokens (FCM push)
    CREATE TABLE IF NOT EXISTS device_tokens (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      token TEXT NOT NULL,
      platform VARCHAR(10) DEFAULT 'android',
      updated_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(user_id, token)
    );

    -- Media uploads
    CREATE TABLE IF NOT EXISTS media (
      id SERIAL PRIMARY KEY,
      incident_id INTEGER REFERENCES incidents(id) ON DELETE SET NULL,
      uploaded_by INTEGER REFERENCES users(id),
      storage_key TEXT,
      content_type VARCHAR(100),
      file_path TEXT,
      lat DOUBLE PRECISION,
      lon DOUBLE PRECISION,
      status VARCHAR(20) DEFAULT 'pending',
      uploaded_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- Preparedness content (disaster guides)
    CREATE TABLE IF NOT EXISTS preparedness_content (
      id SERIAL PRIMARY KEY,
      title VARCHAR(200) NOT NULL,
      category VARCHAR(50) DEFAULT 'general',
      content TEXT NOT NULL,
      parish VARCHAR(50),
      sort_order INTEGER DEFAULT 0,
      published BOOLEAN DEFAULT TRUE,
      created_by INTEGER REFERENCES users(id),
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- SMS / WhatsApp incidents log
    CREATE TABLE IF NOT EXISTS sms_incidents (
      id SERIAL PRIMARY KEY,
      from_number VARCHAR(20) NOT NULL,
      raw_message TEXT NOT NULL,
      parsed_type VARCHAR(50),
      parsed_location TEXT,
      parsed_people INTEGER,
      incident_id INTEGER REFERENCES incidents(id),
      status VARCHAR(20) DEFAULT 'pending',
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  // Migration columns (same as server.js ALTER TABLE block)
  await client.query(`
    ALTER TABLE users ADD COLUMN IF NOT EXISTS vehicle VARCHAR(20);
    ALTER TABLE users ADD COLUMN IF NOT EXISTS availability VARCHAR(20) DEFAULT 'available';
    ALTER TABLE users ADD COLUMN IF NOT EXISTS languages JSONB;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS last_lat DOUBLE PRECISION;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS last_lon DOUBLE PRECISION;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMPTZ;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50) UNIQUE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(100);
    ALTER TABLE incidents ADD COLUMN IF NOT EXISTS people_affected INTEGER;
    ALTER TABLE incidents ADD COLUMN IF NOT EXISTS reference_number VARCHAR(50);
    ALTER TABLE incidents ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'app';
    ALTER TABLE incidents ADD COLUMN IF NOT EXISTS source_phone VARCHAR(20);
    ALTER TABLE incidents ADD COLUMN IF NOT EXISTS resource_needs JSONB;
  `);

  console.log('Schema ensured');
}

// ============================================================
// Reference data
// ============================================================

const parishes = [
  { name: 'Kingston',        lat: 17.9712, lon: -76.7936 },
  { name: 'Saint Andrew',    lat: 18.0800, lon: -76.7800 },
  { name: 'Saint Thomas',    lat: 17.9200, lon: -76.3500 },
  { name: 'Portland',        lat: 18.1500, lon: -76.4200 },
  { name: 'Saint Mary',      lat: 18.3700, lon: -76.9000 },
  { name: 'Saint Ann',       lat: 18.4300, lon: -77.2000 },
  { name: 'Trelawny',        lat: 18.3500, lon: -77.6500 },
  { name: 'Saint James',     lat: 18.4700, lon: -77.9200 },
  { name: 'Hanover',         lat: 18.4000, lon: -78.1300 },
  { name: 'Westmoreland',    lat: 18.2200, lon: -78.1000 },
  { name: 'Saint Elizabeth', lat: 18.0500, lon: -77.7000 },
  { name: 'Manchester',      lat: 18.0500, lon: -77.5000 },
  { name: 'Clarendon',       lat: 17.9500, lon: -77.2000 },
  { name: 'Saint Catherine', lat: 18.0500, lon: -77.0500 },
];

const incidentTemplates = [
  { type: 'medical',  severity: 4, description: 'Heart attack victim needs immediate evacuation',         disasterType: 'other'     },
  { type: 'fire',     severity: 5, description: 'Apartment building fire with people trapped',            disasterType: 'fire'      },
  { type: 'flood',    severity: 3, description: 'Streets flooded, residents need sandbags and evacuation', disasterType: 'hurricane' },
  { type: 'trapped',  severity: 5, description: 'Family of 4 trapped under collapsed roof',               disasterType: 'earthquake'},
  { type: 'medical',  severity: 3, description: 'Multiple injuries at bus accident site',                 disasterType: 'other'     },
  { type: 'fire',     severity: 4, description: 'Wildfire approaching residential area',                  disasterType: 'fire'      },
  { type: 'flood',    severity: 4, description: 'Flash flood warning - 20 people need rescue',            disasterType: 'flood'     },
  { type: 'trapped',  severity: 3, description: 'Elderly woman trapped in rising water',                  disasterType: 'flood'     },
  { type: 'medical',  severity: 2, description: 'Diabetic patient needs insulin delivery',                disasterType: 'other'     },
  { type: 'other',    severity: 2, description: 'Power lines down blocking main road',                    disasterType: 'hurricane' },
  { type: 'medical',  severity: 5, description: 'Pregnant woman in labour, road blocked',                 disasterType: 'other'     },
  { type: 'fire',     severity: 3, description: 'Gas leak reported in commercial area',                   disasterType: 'fire'      },
  { type: 'flood',    severity: 2, description: 'Community isolated, need food and water',                disasterType: 'flood'     },
  { type: 'trapped',  severity: 4, description: 'Child trapped in debris after wall collapse',            disasterType: 'earthquake'},
  { type: 'medical',  severity: 3, description: 'COVID-19 outbreak at shelter, need PPE',                 disasterType: 'other'     },
];

const resourceTypes = [
  { type: 'water',       unit: 'liters',   baseQty: 5000 },
  { type: 'food',        unit: 'packages', baseQty: 2000 },
  { type: 'medical',     unit: 'kits',     baseQty: 500  },
  { type: 'shelter',     unit: 'spaces',   baseQty: 200  },
  { type: 'rescue_team', unit: 'teams',    baseQty: 15   },
];

// -- User definitions (separated by role) ----------------------

const victims = [
  { phone: '+18769001001' },
  { phone: '+18769001002' },
  { phone: '+18769001003' },
  { phone: '+18769001004' },
  { phone: '+18769001005' },
  { phone: '+18769001006' },
  { phone: '+18769001007' },
  { phone: '+18769001008' },
  { phone: '+18769001009' },
  { phone: '+18769001010' },
];

const volunteers = [
  { username: 'vol_johnson',  password: 'VolPass123!',  skills: ['First Aid/CPR', 'Basic Life Support'] },
  { username: 'vol_williams', password: 'VolPass234!',  skills: ['Search & Rescue', 'Heavy Equipment Operation'] },
  { username: 'vol_brown',    password: 'VolPass345!',  skills: ['Logistics', 'Supply Chain Management'] },
  { username: 'vol_davis',    password: 'VolPass456!',  skills: ['Multilingual', 'Spanish', 'French'] },
  { username: 'vol_taylor',   password: 'VolPass567!',  skills: ['Mental Health', 'Crisis Counseling'] },
];

const responders = [
  { username: 'resp_anderson', password: 'RespPass123!', skills: ['Emergency Medicine', 'Advanced Trauma Care', 'First Aid/CPR'] },
  { username: 'resp_thomas',   password: 'RespPass234!', skills: ['Firefighting', 'Hazmat Training', 'Search & Rescue'] },
  { username: 'resp_jackson',  password: 'RespPass345!', skills: ['Emergency Communications', 'Radio Operations', 'Incident Command'] },
  { username: 'resp_white',    password: 'RespPass456!', skills: ['Swift Water Rescue', 'Flood Response', 'Heavy Equipment Operation'] },
  { username: 'resp_harris',   password: 'RespPass567!', skills: ['Medical Professional', 'Triage', 'Basic Life Support'] },
];

const coordinators = [
  { username: 'coord_martin', password: 'CoordPass123!', skills: ['Incident Management', 'Resource Allocation', 'Emergency Planning'] },
  { username: 'coord_garcia', password: 'CoordPass234!', skills: ['Multi-agency Coordination', 'Communications', 'Public Information'] },
  { username: 'coord_miller', password: 'CoordPass345!', skills: ['Operations Management', 'Logistics', 'Disaster Assessment'] },
  { username: 'coord_wilson', password: 'CoordPass456!', skills: ['Emergency Planning', 'Community Outreach', 'Volunteer Management'] },
  { username: 'coord_moore',  password: 'CoordPass567!', skills: ['Strategic Planning', 'Risk Assessment', 'Budget Management'] },
];

// ============================================================
// Helpers
// ============================================================

function randomPointNear(parish) {
  return {
    lat: parish.lat + (Math.random() - 0.5) * 0.05,
    lon: parish.lon + (Math.random() - 0.5) * 0.05,
  };
}

function point(lon, lat) {
  return `POINT(${lon} ${lat})`;
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function generatePhone() {
  const prefix = Math.floor(100 + Math.random() * 900);
  const line   = Math.floor(1000 + Math.random() * 9000);
  return `+1876${prefix}${line}`;
}

// ============================================================
// Main seed function
// ============================================================

async function seedDatabase() {
  const pool = new Pool({ connectionString: databaseUrl });
  const client = await pool.connect();

  try {
    console.log('Starting database seeding...');

    // Ensure schema exists before anything else
    await ensureSchema(client);

    await client.query('BEGIN');

    // Clear existing data (respects foreign-key order)
    for (const table of [
      'sms_incidents', 'media', 'device_tokens', 'messages',
      'preparedness_content', 'volunteer_stats', 'user_alerts',
      'broadcast_alerts', 'resource_allocations', 'notifications',
      'incident_history', 'processed_requests', 'refresh_tokens', 'otps',
      'resources', 'incidents', 'users',
    ]) {
      await client.query(`DELETE FROM ${table}`);
    }
    console.log('Existing data cleared');

    // -- 1. Victims --------------------------------------------
    console.log('Seeding victims...');
    const victimIds = [];
    for (const v of victims) {
      const p = pick(parishes);
      const pt = randomPointNear(p);
      const days = Math.floor(Math.random() * 30);
      const { rows } = await client.query(
        `INSERT INTO users (phone, role, location, created_at)
         VALUES ($1, 'victim', ST_GeogFromText($2), NOW() - INTERVAL '${days} days')
         RETURNING id`,
        [v.phone, point(pt.lon, pt.lat)]
      );
      victimIds.push(rows[0].id);
    }
    console.log(`   ${victimIds.length} victims`);

    // -- 2. Volunteers ----------------------------------------- 
    console.log('Seeding volunteers...');
    const volunteerIds = [];
    let volunteerIndex = 0;
    for (const parish of parishes) {
      // Randomly choose a number between 2 and 5 for this parish
      const numVolunteers = 2 + Math.floor(Math.random() * 4); // 2 to 5
      for (let i = 0; i < numVolunteers; i++) {
        // Cycle through the volunteers array for skills/usernames
        const v = volunteers[volunteerIndex % volunteers.length];
        volunteerIndex++;
        const pt = randomPointNear(parish);
        const days = Math.floor(Math.random() * 60);
        // Make username unique per parish
        const username = `${v.username}_${parish.name.replace(/\s/g, '').toLowerCase()}_${i+1}`;
        const { rows } = await client.query(
          `INSERT INTO users (username, password_hash, phone, role, skills, location, created_at)
           VALUES ($1, $2, $3, 'volunteer', $4::jsonb, ST_GeogFromText($5), NOW() - INTERVAL '${days} days')
           RETURNING id`,
          [username, v.password, generatePhone(), JSON.stringify(v.skills), point(pt.lon, pt.lat)]
        );
        volunteerIds.push(rows[0].id);
      }
    }
    console.log(`   ${volunteerIds.length} volunteers (2-5 per parish)`);

    // -- 3. Responders -----------------------------------------
    console.log('Seeding responders...');
    const responderIds = [];
    for (const r of responders) {
      const p = pick(parishes);
      const pt = randomPointNear(p);
      const days = Math.floor(Math.random() * 60);
      const { rows } = await client.query(
        `INSERT INTO users (username, password_hash, phone, role, skills, location, created_at)
         VALUES ($1, $2, $3, 'responder', $4::jsonb, ST_GeogFromText($5), NOW() - INTERVAL '${days} days')
         RETURNING id`,
        [r.username, r.password, generatePhone(), JSON.stringify(r.skills), point(pt.lon, pt.lat)]
      );
      responderIds.push(rows[0].id);
    }
    console.log(`   ${responderIds.length} responders`);

    // -- 4. Coordinators ---------------------------------------
    console.log('Seeding coordinators...');
    const coordinatorIds = [];
    for (const c of coordinators) {
      const p = pick(parishes);
      const pt = randomPointNear(p);
      const days = Math.floor(Math.random() * 90);
      const { rows } = await client.query(
        `INSERT INTO users (username, password_hash, phone, role, skills, location, created_at)
         VALUES ($1, $2, $3, 'coordinator', $4::jsonb, ST_GeogFromText($5), NOW() - INTERVAL '${days} days')
         RETURNING id`,
        [c.username, c.password, generatePhone(), JSON.stringify(c.skills), point(pt.lon, pt.lat)]
      );
      coordinatorIds.push(rows[0].id);
    }
    console.log(`   ${coordinatorIds.length} coordinators`);

    // -- 5. Incidents ------------------------------------------
    console.log('Seeding incidents...');
    const allResponders = [...volunteerIds, ...responderIds];
    const statuses = ['active', 'in-progress', 'resolved', 'active', 'active'];
    const incidentIds = [];

    // Helper for resource estimation (same as backend)
    function estimateIncidentResources(incident) {
      const base = {
        medical: { water: 10, food: 5, medical: 2, shelter: 1, rescue_team: 1 },
        fire: { water: 20, food: 5, medical: 2, shelter: 1, rescue_team: 2 },
        flood: { water: 30, food: 10, medical: 3, shelter: 2, rescue_team: 3 },
        trapped: { water: 5, food: 2, medical: 2, shelter: 1, rescue_team: 2 },
        supplies: { water: 5, food: 20, medical: 1, shelter: 1, rescue_team: 0 },
        shelter: { water: 10, food: 10, medical: 1, shelter: 5, rescue_team: 0 },
        other: { water: 5, food: 5, medical: 1, shelter: 1, rescue_team: 0 },
      };
      const type = (incident.type || 'other').toLowerCase();
      const people = incident.people_affected || 1;
      const severity = incident.severity || 3;
      const baseNeeds = base[type] || base['other'];
      const needs = {};
      for (const k in baseNeeds) {
        needs[k] = Math.ceil(baseNeeds[k] * people * (0.5 + 0.25 * severity));
      }
      return needs;
    }

    for (const t of incidentTemplates) {
      const p = pick(parishes);
      const pt = randomPointNear(p);
      const status = pick(statuses);
      const submittedBy = Math.random() > 0.3 ? pick(victimIds) : null;
      const assignedTo = status !== 'active' ? pick(allResponders) : null;
      const daysAgo = Math.floor(Math.random() * 7);
      const hoursAgo = Math.floor(Math.random() * 24);
      const areaId = p.name.toLowerCase().replace(/ /g, '_');
      const peopleAffected = 1 + Math.floor(Math.random() * 10);
      const resourceNeeds = estimateIncidentResources({ type: t.type, severity: t.severity, people_affected: peopleAffected });

      const { rows } = await client.query(
        `INSERT INTO incidents
           (type, location, severity, description, disaster_type, area_id,
            status, submitted_by, assigned_to, people_affected, resource_needs, created_at, updated_at)
         VALUES
           ($1, ST_GeogFromText($2), $3, $4, $5, $6,
            $7, $8, $9, $10, $11,
            NOW() - INTERVAL '${daysAgo} days ${hoursAgo} hours',
            NOW() - INTERVAL '${daysAgo} days ${hoursAgo} hours')
         RETURNING id`,
        [
          t.type,
          point(pt.lon, pt.lat),
          t.severity,
          `${t.description} (${p.name})`,
          t.disasterType,
          areaId,
          status,
          submittedBy,
          assignedTo,
          peopleAffected,
          JSON.stringify(resourceNeeds),
        ]
      );
      incidentIds.push(rows[0].id);
    }
    console.log(`   ${incidentIds.length} incidents`);

    // -- 6. Resources ------------------------------------------
    console.log('Seeding resources...');
    const resourceIds = [];
    for (const rt of resourceTypes) {
      const count = 2 + Math.floor(Math.random() * 3);
      for (let i = 0; i < count; i++) {
        const p = pick(parishes);
        const pt = randomPointNear(p);
        const qty = Math.floor(rt.baseQty * (0.3 + Math.random() * 0.7));
        const days = Math.floor(Math.random() * 5);
        const { rows } = await client.query(
          `INSERT INTO resources (type, quantity, unit, location, organisation_id, status, last_updated)
           VALUES ($1, $2, $3, ST_GeogFromText($4), $5, 'available', NOW() - INTERVAL '${days} days')
           RETURNING id`,
          [rt.type, qty, rt.unit, point(pt.lon, pt.lat), pick(coordinatorIds)]
        );
        resourceIds.push(rows[0].id);
      }
    }
    console.log(`   ${resourceIds.length} resources`);

    // -- 7. Resource allocations -------------------------------
    console.log('Seeding resource allocations...');
    for (let i = 0; i < 8; i++) {
      const days = Math.floor(Math.random() * 3);
      await client.query(
        `INSERT INTO resource_allocations (resource_id, incident_id, quantity, allocated_at)
         VALUES ($1, $2, $3, NOW() - INTERVAL '${days} days')`,
        [pick(resourceIds), pick(incidentIds), 5 + Math.floor(Math.random() * 50)]
      );
    }
    console.log('   8 resource allocations');

    // -- 8. Incident history -----------------------------------
    console.log('Seeding incident history...');
    for (const incidentId of incidentIds) {
      const { rows } = await client.query(
        'SELECT status, created_at FROM incidents WHERE id = $1',
        [incidentId]
      );
      if (rows.length > 0) {
        const created = new Date(rows[0].created_at);
        await client.query(
          `INSERT INTO incident_history (incident_id, from_status, to_status, changed_by, changed_at)
           VALUES ($1, 'submitted', $2, $3, $4)`,
          [incidentId, rows[0].status, pick(coordinatorIds), new Date(created.getTime() + 30 * 60000)]
        );
        // Add a second history entry for non-active incidents
        if (rows[0].status !== 'active') {
          await client.query(
            `INSERT INTO incident_history (incident_id, from_status, to_status, changed_by, changed_at)
             VALUES ($1, 'active', $2, $3, $4)`,
            [incidentId, rows[0].status, pick(coordinatorIds), new Date(created.getTime() + 90 * 60000)]
          );
        }
      }
    }
    console.log(`   ${incidentIds.length}+ history entries`);

    // -- 9. Notifications --------------------------------------
    console.log('Seeding notifications...');
    const notifTypes = [
      { type: 'INCIDENT_ASSIGNED', make: (iId) => ({ message: `You have been assigned to incident #${iId}`, incidentId: String(iId) }) },
      { type: 'STATUS_UPDATE',     make: (iId) => ({ message: `Incident #${iId} status changed to in-progress`, incidentId: String(iId) }) },
      { type: 'BROADCAST_ALERT',   make: ()    => ({ message: 'Hurricane warning issued for your area. Seek shelter immediately.' }) },
      { type: 'TASK_COMPLETED',    make: (iId) => ({ message: `Incident #${iId} has been resolved. Thank you!`, incidentId: String(iId) }) },
      { type: 'NEW_MESSAGE',       make: (iId) => ({ message: `New message on incident #${iId}`, incidentId: String(iId) }) },
    ];
    let notifCount = 0;
    const allUserIds = [...victimIds, ...volunteerIds, ...responderIds, ...coordinatorIds];
    for (let i = 0; i < 30; i++) {
      const userId = pick(allUserIds);
      const n = pick(notifTypes);
      const incId = pick(incidentIds);
      const daysAgo = Math.floor(Math.random() * 7);
      const hoursAgo = Math.floor(Math.random() * 24);
      const isRead = Math.random() > 0.5;
      await client.query(
        `INSERT INTO notifications (user_id, type, data, read, created_at)
         VALUES ($1, $2, $3, $4, NOW() - INTERVAL '${daysAgo} days ${hoursAgo} hours')`,
        [userId, n.type, JSON.stringify(n.make(incId)), isRead]
      );
      notifCount++;
    }
    console.log(`   ${notifCount} notifications`);

    // -- 10. Broadcast alerts & user_alerts --------------------
    console.log('Seeding broadcast alerts...');
    const broadcastMessages = [
      { message: '⚠️ HURRICANE WARNING: Category 3 hurricane approaching southern coast. All residents in coastal areas should evacuate immediately to designated shelters.', roles: 'all', hours: 2 },
      { message: '🏥 MEDICAL SUPPLIES: Emergency medical supplies have arrived at Kingston General Hospital. Volunteers needed for distribution.', roles: 'volunteer,responder', hours: 12 },
      { message: '🚧 ROAD CLOSURE: A3 highway blocked between Spanish Town and May Pen due to flooding. Use alternate routes via B12.', roles: 'all', hours: 24 },
      { message: '🆘 URGENT: Shelter at National Arena is at capacity. Directing overflow to UWI Mona campus. Coordinators please update routing.', roles: 'coordinator', hours: 6 },
      { message: '✅ ALL CLEAR: Flood waters receding in Portland parish. Residents may begin returning home. Exercise caution on roads.', roles: 'all', hours: 48 },
      { message: '📦 SUPPLY DROP: Water and food packages available at Half Way Tree Transport Centre. Bring ID.', roles: 'all', hours: 8 },
    ];
    const alertIds = [];
    for (const b of broadcastMessages) {
      const { rows } = await client.query(
        `INSERT INTO broadcast_alerts (message, target_roles, expires_at, created_by, created_at)
         VALUES ($1, $2, NOW() + INTERVAL '${b.hours} hours', $3, NOW() - INTERVAL '${Math.floor(Math.random() * 3)} hours')
         RETURNING id`,
        [b.message, b.roles, pick(coordinatorIds)]
      );
      alertIds.push(rows[0].id);
    }
    console.log(`   ${alertIds.length} broadcast alerts`);

    // Acknowledge some alerts
    let ackCount = 0;
    for (const alertId of alertIds) {
      const recipients = allUserIds.sort(() => Math.random() - 0.5).slice(0, 5 + Math.floor(Math.random() * 10));
      for (const userId of recipients) {
        const acked = Math.random() > 0.3;
        await client.query(
          `INSERT INTO user_alerts (user_id, alert_id, acknowledged, acknowledged_at, delivered_via)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (user_id, alert_id) DO NOTHING`,
          [
            userId, alertId, acked,
            acked ? new Date(Date.now() - Math.floor(Math.random() * 3600000)) : null,
            pick(['push', 'push', 'push', 'in_app']),
          ]
        );
        ackCount++;
      }
    }
    console.log(`   ${ackCount} user_alert deliveries`);

    // -- 11. Volunteer stats / gamification --------------------
    console.log('Seeding volunteer stats...');
    const badgePool = [
      'First Responder', 'Night Owl', 'Community Hero', 'Quick Responder',
      'Marathon Helper', '100 Hours', 'Streak Master', 'Life Saver',
      'Supply Runner', 'Team Leader',
    ];
    for (const volId of volunteerIds) {
      const tasksCompleted = Math.floor(Math.random() * 25);
      const hours = +(Math.random() * 120).toFixed(2);
      const streakDays = Math.floor(Math.random() * 14);
      const numBadges = Math.floor(Math.random() * 4);
      const badges = [];
      for (let b = 0; b < numBadges; b++) {
        const badge = pick(badgePool);
        if (!badges.find(x => x.name === badge)) {
          badges.push({ name: badge, awardedAt: new Date(Date.now() - Math.random() * 30 * 86400000).toISOString() });
        }
      }
      await client.query(
        `INSERT INTO volunteer_stats (user_id, tasks_completed, hours_contributed, badges, streak_days, last_active_at, leaderboard_opt_in)
         VALUES ($1, $2, $3, $4, $5, NOW() - INTERVAL '${Math.floor(Math.random() * 48)} hours', $6)`,
        [volId, tasksCompleted, hours, JSON.stringify(badges), streakDays, Math.random() > 0.3]
      );
    }
    // Also seed stats for responders
    for (const respId of responderIds) {
      const tasksCompleted = 5 + Math.floor(Math.random() * 30);
      const hours = +(20 + Math.random() * 200).toFixed(2);
      const streakDays = Math.floor(Math.random() * 21);
      const numBadges = 1 + Math.floor(Math.random() * 5);
      const badges = [];
      for (let b = 0; b < numBadges; b++) {
        const badge = pick(badgePool);
        if (!badges.find(x => x.name === badge)) {
          badges.push({ name: badge, awardedAt: new Date(Date.now() - Math.random() * 60 * 86400000).toISOString() });
        }
      }
      await client.query(
        `INSERT INTO volunteer_stats (user_id, tasks_completed, hours_contributed, badges, streak_days, last_active_at, leaderboard_opt_in)
         VALUES ($1, $2, $3, $4, $5, NOW() - INTERVAL '${Math.floor(Math.random() * 24)} hours', $6)`,
        [respId, tasksCompleted, hours, JSON.stringify(badges), streakDays, Math.random() > 0.2]
      );
    }
    console.log(`   ${volunteerIds.length + responderIds.length} volunteer stats`);

    // -- 12. Messages (two-way chat) ---------------------------
    console.log('Seeding messages...');
    const chatTemplates = [
      { from: 'victim',      content: 'We need help urgently, water is rising!' },
      { from: 'coordinator', content: 'Help is on the way. A rescue team has been dispatched.' },
      { from: 'victim',      content: 'There are 3 children and 2 elderly people here.' },
      { from: 'responder',   content: 'We are 10 minutes away. Stay on a high floor if possible.' },
      { from: 'victim',      content: 'Thank you, we are on the second floor now.' },
      { from: 'responder',   content: 'We have arrived. Opening the north entrance now.' },
      { from: 'coordinator', content: 'Confirmed extraction successful. Marking incident resolved.' },
      { from: 'volunteer',   content: 'I have extra blankets and water at the staging area.' },
      { from: 'coordinator', content: 'Great, bring them to the Half Way Tree shelter please.' },
      { from: 'volunteer',   content: 'On my way, ETA 15 minutes.' },
      { from: 'victim',      content: 'Is it safe to return home now?' },
      { from: 'coordinator', content: 'Not yet. We will send an all-clear notification when it is safe.' },
      { from: 'responder',   content: 'Road blocked at Old Hope Road. Taking alternate route via Barbican.' },
      { from: 'coordinator', content: 'Copy. Updating the route for other responders.' },
      { from: 'victim',      content: 'My neighbour is injured and cannot walk. Please bring a stretcher.' },
    ];
    let msgCount = 0;
    // Create conversation threads for some incidents
    const chatIncidents = incidentIds.slice(0, 8);
    for (const incId of chatIncidents) {
      const threadLength = 3 + Math.floor(Math.random() * 5);
      for (let m = 0; m < threadLength; m++) {
        const tmpl = chatTemplates[m % chatTemplates.length];
        let senderId;
        if (tmpl.from === 'victim')      senderId = pick(victimIds);
        else if (tmpl.from === 'volunteer')   senderId = pick(volunteerIds);
        else if (tmpl.from === 'responder')   senderId = pick(responderIds);
        else                                  senderId = pick(coordinatorIds);
        const minsAgo = (threadLength - m) * (5 + Math.floor(Math.random() * 10));
        await client.query(
          `INSERT INTO messages (incident_id, sender_id, content, message_type, delivered, read, created_at)
           VALUES ($1, $2, $3, 'text', $4, $5, NOW() - INTERVAL '${minsAgo} minutes')`,
          [incId, senderId, tmpl.content, Math.random() > 0.1, Math.random() > 0.3]
        );
        msgCount++;
      }
    }
    console.log(`   ${msgCount} messages across ${chatIncidents.length} incident threads`);

    // -- 13. Preparedness content (disaster guides) ------------
    console.log('Seeding preparedness content...');
    const guides = [
      { title: 'Hurricane Preparedness Guide',  category: 'hurricane', parish: null, content: `
## Before the Hurricane
- Stock at least 3 days of water (1 gallon per person per day)
- Secure loose outdoor items (zinc sheets, furniture, garbage bins)
- Charge all devices and portable batteries
- Know your nearest shelter: check ODPEM website or call 116
- Fill bathtub with water for flushing/cleaning

## During the Hurricane
- Stay indoors away from windows and glass doors
- Move to the strongest room in your home (bathroom, closet)
- If flooding starts, move to the highest floor
- Do NOT attempt to drive through flooded roads
- Listen to JIS (Jamaica Information Service) for updates

## After the Hurricane
- Wait for official all-clear before going outside
- Avoid downed power lines and standing water
- Check on neighbours, especially elderly and disabled
- Document damage with photos for insurance claims
- Boil tap water until water supply is confirmed safe` },

      { title: 'Earthquake Safety',  category: 'earthquake', parish: null, content: `
## During an Earthquake
- DROP to your hands and knees
- Take COVER under a sturdy desk or table
- HOLD ON until the shaking stops
- If outdoors, move to an open area away from buildings
- If driving, pull over and stay in vehicle

## After an Earthquake
- Check yourself and others for injuries
- Exit damaged buildings carefully
- Expect aftershocks — they can be strong
- Do not use elevators
- Check gas lines and water pipes for damage
- Text instead of calling to keep lines clear for emergencies` },

      { title: 'Flood Response Guide',  category: 'flood', parish: null, content: `
## Flood Warning Signs
- Heavy rainfall lasting more than 2 hours
- Rivers and gullies rising rapidly
- Water entering low-lying areas
- Jamaica Met Service flood warnings

## What to Do
- Move to higher ground immediately — do not wait
- Never walk, swim, or drive through flood waters
- 6 inches of moving water can knock you down
- 2 feet of water can float a vehicle
- Stay off bridges over fast-moving water

## After Flooding
- Return home only when authorities say it is safe
- Clean and disinfect everything that got wet
- Throw away food that came in contact with flood water
- Watch for snakes and insects displaced by flooding` },

      { title: 'Emergency Go-Bag Checklist',  category: 'general', parish: null, content: `
## Essential Items (72-Hour Kit)
- Water: 1 gallon per person per day (3-day supply)
- Non-perishable food: canned goods, crackers, dried fruit
- Manual can opener
- Flashlight with extra batteries
- First aid kit
- Medications (7-day supply)
- Important documents in waterproof bag (ID, passport, insurance)
- Cash in small bills (ATMs may be down)
- Phone charger and portable battery bank
- Whistle (to signal for help)

## Additional Items
- Change of clothes and sturdy shoes
- Blankets or sleeping bags
- Toiletries and sanitation supplies
- Baby supplies if needed (formula, diapers)
- Pet food and supplies if needed
- Local map (phone GPS may not work)` },

      { title: 'Fire Safety at Home',  category: 'fire', parish: null, content: `
## Prevention
- Never leave cooking unattended
- Keep flammable items away from stove and heat sources
- Check electrical wiring regularly — frayed wires cause fires
- Do not overload extension cords or outlets
- Store kerosene and gas cylinders away from heat

## If a Fire Starts
- GET OUT immediately — do not stop to collect belongings
- Crawl low under smoke (cleaner air is near the floor)
- Feel doors before opening — if hot, use another exit
- Call 110 (Jamaica Fire Brigade) once you are safe
- Meet at your pre-arranged assembly point

## Escape Planning
- Know 2 exits from every room
- Practice fire drills with your household
- Keep keys near doors (but not visible from outside)
- If trapped, seal door gaps with wet cloth and signal from window` },

      { title: 'Kingston & St Andrew Shelters',  category: 'shelters', parish: 'Kingston', content: `
## Official Emergency Shelters
- National Arena, Independence Park — capacity 3,000
- National Indoor Sports Centre — capacity 2,000
- Excelsior High School — capacity 500
- Wolmer's Boys' School — capacity 400
- Holy Trinity Cathedral — capacity 300
- UWI Mona Assembly Hall — capacity 1,500

## What to Bring to a Shelter
- Your emergency go-bag (see Go-Bag Checklist)
- Personal medications
- Bedding (sheet, blanket or sleeping bag)
- Identification documents
- Infant supplies if needed

Contact ODPEM: 876-906-9674 or dial 116` },

      { title: 'St James & Montego Bay Shelters',  category: 'shelters', parish: 'Saint James', content: `
## Official Emergency Shelters
- Montego Bay Convention Centre — capacity 2,500
- Catherine Hall Primary — capacity 350
- St James High School — capacity 400
- Montego Bay Community College — capacity 600

## Coastal Evacuation Routes
- Follow B15 inland from Montego Bay towards Anchovy
- Avoid Howard Cooke Boulevard during storm surge
- Report to nearest shelter if road is impassable

Contact ODPEM Western: 876-952-1838` },

      { title: 'Portland Parish Guide',  category: 'flood', parish: 'Portland', content: `
## Flood-Prone Areas
- Port Antonio town centre (near Rio Grande)
- Hope Bay river basin
- Buff Bay lowlands
- Long Bay coastal road

## Key Actions
- Monitor Rio Grande and Swift River water levels
- Evacuate from river banks when heavy rain persists
- Use John Crow Mountains high roads as escape routes
- Shelter at Titchfield High (Port Antonio) or Portland Parish Church

Portland is one of Jamaica's wettest parishes — always have a go-bag ready during hurricane season (June–November).` },
    ];
    let guideCount = 0;
    for (let i = 0; i < guides.length; i++) {
      const g = guides[i];
      await client.query(
        `INSERT INTO preparedness_content (title, category, content, parish, sort_order, published, created_by)
         VALUES ($1, $2, $3, $4, $5, TRUE, $6)`,
        [g.title, g.category, g.content.trim(), g.parish, i + 1, pick(coordinatorIds)]
      );
      guideCount++;
    }
    console.log(`   ${guideCount} preparedness guides`);

    // -- 14. Media records (metadata only, no actual files) ----
    console.log('Seeding media records...');
    const mediaTemplates = [
      { key: 'flood_damage_01.jpg',  type: 'image/jpeg' },
      { key: 'collapsed_roof_01.jpg', type: 'image/jpeg' },
      { key: 'road_blocked_01.jpg',  type: 'image/jpeg' },
      { key: 'rescue_team_01.jpg',   type: 'image/jpeg' },
      { key: 'shelter_setup_01.jpg', type: 'image/jpeg' },
      { key: 'supply_drop_01.jpg',   type: 'image/jpeg' },
      { key: 'fire_scene_01.jpg',    type: 'image/jpeg' },
      { key: 'medical_aid_01.jpg',   type: 'image/jpeg' },
    ];
    let mediaCount = 0;
    for (const incId of incidentIds.slice(0, 10)) {
      const numPhotos = 1 + Math.floor(Math.random() * 3);
      for (let m = 0; m < numPhotos; m++) {
        const tmpl = pick(mediaTemplates);
        const p = pick(parishes);
        const pt = randomPointNear(p);
        const hoursAgo = Math.floor(Math.random() * 48);
        await client.query(
          `INSERT INTO media (incident_id, uploaded_by, storage_key, content_type, lat, lon, status, uploaded_at, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, 'uploaded', NOW() - INTERVAL '${hoursAgo} hours', NOW() - INTERVAL '${hoursAgo} hours')`,
          [incId, pick([...victimIds, ...responderIds]), `incidents/${incId}/${tmpl.key}`, tmpl.type, pt.lat, pt.lon]
        );
        mediaCount++;
      }
    }
    console.log(`   ${mediaCount} media records`);

    // -- 15. SMS/WhatsApp incidents ----------------------------
    console.log('Seeding WhatsApp/SMS incidents...');
    const smsMessages = [
      { raw: 'HELP MEDICAL 14 Palm Street Kingston 2 people',    type: 'medical_emergency', location: '14 Palm Street Kingston',     people: 2 },
      { raw: 'TRAPPED old warehouse by the harbour Port Royal',   type: 'trapped',           location: 'old warehouse Port Royal',    people: 1 },
      { raw: 'SUPPLIES need water and food St Andrew 5 people',   type: 'need_supplies',     location: 'St Andrew',                   people: 5 },
      { raw: 'SHELTER 8 people need shelter in Portmore',         type: 'shelter',            location: 'Portmore',                    people: 8 },
      { raw: 'MEDICAL elderly man collapsed at Half Way Tree',    type: 'medical_emergency', location: 'Half Way Tree',               people: 1 },
    ];
    for (const sms of smsMessages) {
      const matchingIncident = pick(incidentIds);
      await client.query(
        `INSERT INTO sms_incidents (from_number, raw_message, parsed_type, parsed_location, parsed_people, incident_id, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'created')`,
        ['+1876' + Math.floor(1000000 + Math.random() * 9000000), sms.raw, sms.type, sms.location, sms.people, matchingIncident]
      );
    }
    console.log(`   ${smsMessages.length} WhatsApp/SMS incidents`);

    // -- Commit ------------------------------------------------
    await client.query('COMMIT');

    console.log('\n✅ Seeding completed successfully!\n');
    console.log('Summary:');
    console.log(`   Victims:             ${victimIds.length}`);
    console.log(`   Volunteers:          ${volunteerIds.length}`);
    console.log(`   Responders:          ${responderIds.length}`);
    console.log(`   Coordinators:        ${coordinatorIds.length}`);
    console.log(`   Incidents:           ${incidentIds.length}`);
    console.log(`   Resources:           ${resourceIds.length}`);
    console.log(`   Allocations:         8`);
    console.log(`   Notifications:       ${notifCount}`);
    console.log(`   Broadcast alerts:    ${alertIds.length}`);
    console.log(`   Volunteer stats:     ${volunteerIds.length + responderIds.length}`);
    console.log(`   Messages:            ${msgCount}`);
    console.log(`   Preparedness guides: ${guideCount}`);
    console.log(`   Media records:       ${mediaCount}`);
    console.log(`   SMS/WA incidents:    ${smsMessages.length}`);
    console.log('\nLogin credentials:');
    console.log('   -- Volunteers --');
    for (const v of volunteers) {
      console.log(`   ${v.username} / ${v.password}  (skills: ${v.skills.join(', ')})`);
    }
    console.log('   -- Responders --');
    for (const r of responders) {
      console.log(`   ${r.username} / ${r.password}  (skills: ${r.skills.join(', ')})`);
    }
    console.log('   -- Coordinators --');
    for (const c of coordinators) {
      console.log(`   ${c.username} / ${c.password}  (skills: ${c.skills.join(', ')})`);
    }
    console.log('\n   Victims: any phone + any 6-digit OTP (TESTING_MODE)\n');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seeding failed:', err);
  } finally {
    client.release();
    await pool.end();
  }
}

ensureDatabaseExists().then(() => seedDatabase());
