const express = require('express');
const cors = require('cors');
const http = require('http');
const https = require('https');
const socketIo = require('socket.io');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const path = require('path');
const os = require('os');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: { origin: '*', methods: ['GET', 'POST', 'PATCH', 'DELETE'] }
});

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const MOCK_AUTH = process.env.MOCK_AUTH === 'true';

// Mock auth middleware — sets req.user when MOCK_AUTH=true
if (MOCK_AUTH) {
  app.use((req, res, next) => {
    req.user = { id: 1, phone: '+18761234567', role: 'coordinator' };
    next();
  });
}

const sslConfig = process.env.DATABASE_SSL === 'true'
  ? { rejectUnauthorized: false }
  : false;

function quoteIdentifier(name) {
  return `"${name.replace(/"/g, '""')}"`;
}

// ============================================================
// Vonage (Nexmo) SMS Utility
// ============================================================
const VONAGE_API_KEY = process.env.VONAGE_API_KEY;
const VONAGE_API_SECRET = process.env.VONAGE_API_SECRET;
const VONAGE_FROM = process.env.VONAGE_FROM || 'ReddiHelp';
const MAPBOX_TOKEN = process.env.MAPBOX_ACCESS_TOKEN || process.env.VITE_MAPBOX_TOKEN || '';

async function sendSMS(to, text) {
  if (!VONAGE_API_KEY || !VONAGE_API_SECRET) {
    console.log(`📱 [SMS-MOCK] → ${to}: ${text}`);
    return { mock: true };
  }
  const payload = JSON.stringify({
    api_key: VONAGE_API_KEY,
    api_secret: VONAGE_API_SECRET,
    to: to.replace(/[^0-9+]/g, ''),
    from: VONAGE_FROM,
    text,
  });
  return new Promise((resolve, reject) => {
    const req = https.request(
      { hostname: 'rest.nexmo.com', path: '/sms/json', method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } },
      (res) => {
        let body = '';
        res.on('data', (d) => (body += d));
        res.on('end', () => {
          try { const j = JSON.parse(body); resolve(j); } catch { resolve({ raw: body }); }
        });
      }
    );
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function geocodeAddress(address) {
  if (!MAPBOX_TOKEN || !address || address === 'Unknown location') return null;

}
const databaseUrl = process.env.DATABASE_URL;

let pgPool;

async function ensureDatabaseExists() {
  if (!databaseUrl) {
    throw new Error('DATABASE_URL is not set in .env');
  }

  const parsedUrl = new URL(databaseUrl);
  const dbName = parsedUrl.pathname.replace(/^\//, '');

  if (!dbName) {
    throw new Error('DATABASE_URL must include a database name (for example /disaster_response)');
  }

  const maintenanceUrl = new URL(databaseUrl);
  maintenanceUrl.pathname = '/postgres';

  const adminPool = new Pool({
    connectionString: maintenanceUrl.toString(),
    ssl: sslConfig,
  });

  try {
    const existsResult = await adminPool.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [dbName]
    );

    if (existsResult.rowCount === 0) {
      await adminPool.query(`CREATE DATABASE ${quoteIdentifier(dbName)}`);
      console.log(`🛠️  Database created: ${dbName}`);
    }
  } finally {
    await adminPool.end();
  }
}

(async () => {
  try {
    await ensureDatabaseExists();

    pgPool = new Pool({
      connectionString: databaseUrl,
      ssl: sslConfig,
    });

    await pgPool.query(`
      CREATE EXTENSION IF NOT EXISTS postgis;

      -- Users table
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        phone VARCHAR(20) UNIQUE NOT NULL,
        role VARCHAR(20) NOT NULL,
        organisation_id INTEGER,
        skills JSONB,
        location GEOGRAPHY(POINT),
        created_at TIMESTAMPTZ DEFAULT NOW()
      );

      -- Incidents table
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
        resource_needs JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_incidents_location ON incidents USING GIST(location);
      CREATE INDEX IF NOT EXISTS idx_incidents_status_created ON incidents(status, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_incidents_submitted_created ON incidents(submitted_by, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_incidents_assigned_created ON incidents(assigned_to, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_incidents_active_unassigned_created
        ON incidents(created_at DESC)
        WHERE status = 'active' AND assigned_to IS NULL;

      -- Resources table
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

      -- Refresh tokens table
      CREATE TABLE IF NOT EXISTS refresh_tokens (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        token TEXT NOT NULL,
        expires_at TIMESTAMPTZ NOT NULL
      );

      -- Processed requests (idempotency cache for sync)
      CREATE TABLE IF NOT EXISTS processed_requests (
        idempotency_key VARCHAR(255) PRIMARY KEY,
        response JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );

      -- OTP table
      CREATE TABLE IF NOT EXISTS otps (
        phone VARCHAR(20) PRIMARY KEY,
        code VARCHAR(6) NOT NULL,
        expires_at TIMESTAMPTZ NOT NULL
      );

      -- Resource allocations table
      CREATE TABLE IF NOT EXISTS resource_allocations (
        id SERIAL PRIMARY KEY,
        resource_id INTEGER REFERENCES resources(id),
        incident_id INTEGER REFERENCES incidents(id),
        quantity INTEGER NOT NULL,
        allocated_at TIMESTAMPTZ DEFAULT NOW(),
        notes TEXT
      );

      -- Notifications table
      CREATE TABLE IF NOT EXISTS notifications (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        type VARCHAR(50) NOT NULL,
        data JSONB,
        read BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );

      -- Incident history (audit trail)
      CREATE TABLE IF NOT EXISTS incident_history (
        id SERIAL PRIMARY KEY,
        incident_id INTEGER REFERENCES incidents(id),
        from_status VARCHAR(20),
        to_status VARCHAR(20),
        changed_by INTEGER REFERENCES users(id),
        changed_at TIMESTAMPTZ DEFAULT NOW()
      );

      -- Broadcast alerts (#13)
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

      -- Volunteer stats / gamification (#3)
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

      -- Chat messages per incident (#9)
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
      CREATE INDEX IF NOT EXISTS idx_messages_incident ON messages(incident_id, created_at);

      -- Device tokens for FCM push notifications (#5)
      CREATE TABLE IF NOT EXISTS device_tokens (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        token TEXT NOT NULL,
        platform VARCHAR(10) DEFAULT 'android',
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(user_id, token)
      );

      -- Media uploads (#8)
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

      -- Preparedness content CMS (#16)
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
    `);

    // Safely add idempotency_key column to incidents if it was created before this migration
    await pgPool.query(`
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(255) UNIQUE;
    `);

    // Add new columns for enhanced features
    await pgPool.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS vehicle VARCHAR(20);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS availability VARCHAR(20) DEFAULT 'available';
      ALTER TABLE users ADD COLUMN IF NOT EXISTS languages JSONB;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS last_lat DOUBLE PRECISION;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS last_lon DOUBLE PRECISION;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMPTZ;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(50) UNIQUE;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(100);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS active_location_lat DOUBLE PRECISION;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS active_location_lon DOUBLE PRECISION;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS active_location_name VARCHAR(100);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMPTZ;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS check_in_station_name VARCHAR(120);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS check_in_station_parish VARCHAR(120);
      ALTER TABLE users ADD COLUMN IF NOT EXISTS check_in_station_lat DOUBLE PRECISION;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS check_in_station_lon DOUBLE PRECISION;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS people_affected INTEGER;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS reference_number VARCHAR(50);
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'app';
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS source_phone VARCHAR(20);
    `);

    // Phase 4: Resource enhancements
    await pgPool.query(`
      ALTER TABLE resources ADD COLUMN IF NOT EXISTS alert_threshold INTEGER DEFAULT 0;
      ALTER TABLE resources ADD COLUMN IF NOT EXISTS name VARCHAR(100);
      ALTER TABLE resources ADD COLUMN IF NOT EXISTS organisation_name VARCHAR(100);
    `);

    // Phase 5: Broadcast enhancements
    await pgPool.query(`
      ALTER TABLE broadcast_alerts ADD COLUMN IF NOT EXISTS severity VARCHAR(20) DEFAULT 'INFO';
      ALTER TABLE broadcast_alerts ADD COLUMN IF NOT EXISTS title VARCHAR(200);
      ALTER TABLE broadcast_alerts ADD COLUMN IF NOT EXISTS recipient_count INTEGER DEFAULT 0;
      ALTER TABLE broadcast_alerts ADD COLUMN IF NOT EXISTS delivery_count INTEGER DEFAULT 0;
    `);

    // Phase 8: Add note column to incident_history
    await pgPool.query(`
      ALTER TABLE incident_history ADD COLUMN IF NOT EXISTS note TEXT;
    `);

    // Phase 7: Map layers & presets
    await pgPool.query(`
      CREATE TABLE IF NOT EXISTS map_layers (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        type VARCHAR(50),
        geojson JSONB,
        created_by INTEGER REFERENCES users(id),
        created_at TIMESTAMPTZ DEFAULT NOW(),
        active BOOLEAN DEFAULT TRUE
      );
      CREATE TABLE IF NOT EXISTS layer_presets (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        user_id INTEGER REFERENCES users(id),
        layers JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    // Phase 9: Resource requests
    await pgPool.query(`
      CREATE TABLE IF NOT EXISTS resource_requests (
        id SERIAL PRIMARY KEY,
        incident_id INTEGER REFERENCES incidents(id),
        requested_by INTEGER REFERENCES users(id),
        resource_type VARCHAR(50) NOT NULL,
        quantity INTEGER NOT NULL,
        urgency VARCHAR(20) DEFAULT 'normal',
        delivery_lat DOUBLE PRECISION,
        delivery_lon DOUBLE PRECISION,
        status VARCHAR(20) DEFAULT 'pending',
        fulfilled_by INTEGER REFERENCES users(id),
        fulfilled_at TIMESTAMPTZ,
        notes TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    // Phase 10: Generated reports
    await pgPool.query(`
      CREATE TABLE IF NOT EXISTS generated_reports (
        id SERIAL PRIMARY KEY,
        title VARCHAR(200),
        date_range_start TIMESTAMPTZ,
        date_range_end TIMESTAMPTZ,
        generated_by INTEGER REFERENCES users(id),
        file_path TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    // Phase 14: Dispatch decisions
    await pgPool.query(`
      CREATE TABLE IF NOT EXISTS dispatch_decisions (
        id SERIAL PRIMARY KEY,
        incident_id INTEGER REFERENCES incidents(id),
        volunteer_id INTEGER REFERENCES users(id),
        confidence INTEGER,
        decision VARCHAR(20),
        overridden BOOLEAN DEFAULT FALSE,
        decided_at TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    console.log('✅ Database connected and all tables ensured');

    // Insert a default coordinator user if missing (used in MOCK_AUTH mode)
    await pgPool.query(`
      INSERT INTO users (id, phone, role, username, password_hash)
      VALUES (1, '+18761234567', 'coordinator', 'admin', 'admin123')
      ON CONFLICT (id) DO UPDATE
        SET username = EXCLUDED.username,
            password_hash = COALESCE(users.password_hash, EXCLUDED.password_hash);
    `);
    console.log('👤 Default admin user ensured (id=1, username=admin)');
  } catch (err) {
    console.error('❌ Database init error:', err);
    if (err && err.code === '42501') {
      console.error('ℹ️  The current PostgreSQL user does not have permission to create databases.');
      console.error('ℹ️  Create the database manually, then run npm start again.');
    }
  }
})();

// ============================================================
// JWT Helpers
// ============================================================
const ACCESS_TOKEN_SECRET = process.env.ACCESS_TOKEN_SECRET || 'access-secret';
const REFRESH_TOKEN_SECRET = process.env.REFRESH_TOKEN_SECRET || 'refresh-secret';

function generateAccessToken(user) {
  return jwt.sign(
    { id: user.id, phone: user.phone, role: user.role },
    ACCESS_TOKEN_SECRET,
    { expiresIn: '15m' }
  );
}

function generateRefreshToken(user) {
  return jwt.sign({ id: user.id }, REFRESH_TOKEN_SECRET, { expiresIn: '30d' });
}

// Verifies Bearer token. Skipped automatically when MOCK_AUTH=true sets req.user upstream.
function authenticateToken(req, res, next) {
  if (req.user) return next(); // already set by mock middleware

  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.sendStatus(401);

  jwt.verify(token, ACCESS_TOKEN_SECRET, (err, user) => {
    if (err) return res.sendStatus(403);
    req.user = user;
    next();
  });
}

// Role-based access control
function authorize(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.sendStatus(401);
    if (!roles.includes(req.user.role)) return res.sendStatus(403);
    next();
  };
}

// ============================================================
// Health Check
// ============================================================
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ============================================================
// Authentication Endpoints
// ============================================================
app.post('/api/auth/request-otp', async (req, res) => {
  const { phone } = req.body;
  if (!phone) return res.status(400).json({ error: 'Phone required' });

  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  console.log(`📱 OTP for ${phone}: ${otp}`);

  await pgPool.query(
    `INSERT INTO otps (phone, code, expires_at)
     VALUES ($1, $2, NOW() + INTERVAL '5 minutes')
     ON CONFLICT (phone) DO UPDATE
     SET code = $2, expires_at = NOW() + INTERVAL '5 minutes'`,
    [phone, otp]
  );

  res.json({ message: 'OTP sent' });
});

app.post('/api/auth/verify-otp', async (req, res) => {
  const { phone, otp, role = 'victim' } = req.body;

  // TESTING_MODE accepts any 6-digit OTP. Set TESTING_MODE=false in .env for production.
  const TESTING_MODE = process.env.TESTING_MODE !== 'false';

  if (!TESTING_MODE) {
    const result = await pgPool.query(
      'SELECT code FROM otps WHERE phone = $1 AND expires_at > NOW()',
      [phone]
    );
    if (result.rows.length === 0 || result.rows[0].code !== otp) {
      return res.status(401).json({ error: 'Invalid or expired OTP' });
    }
  } else {
    if (!otp || !/^\d{6}$/.test(otp)) {
      return res.status(401).json({ error: 'OTP must be exactly 6 digits' });
    }
    console.log(`🧪 [TESTING_MODE] Accepted OTP ${otp} for ${phone}`);
  }

  await pgPool.query('DELETE FROM otps WHERE phone = $1', [phone]).catch(() => {});

  let userResult = await pgPool.query('SELECT * FROM users WHERE phone = $1', [phone]);
  let user;

  if (userResult.rows.length === 0) {
    const newUser = await pgPool.query(
      'INSERT INTO users (phone, role) VALUES ($1, $2) RETURNING *',
      [phone, role]
    );
    user = newUser.rows[0];
  } else {
    user = userResult.rows[0];
  }

  const accessToken = generateAccessToken(user);
  const refreshToken = generateRefreshToken(user);

  await pgPool.query(
    "INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, NOW() + INTERVAL '30 days')",
    [user.id, refreshToken]
  );

  res.json({
    accessToken,
    refreshToken,
    user: { id: user.id, phone: user.phone, role: user.role },
  });
});

// ── Firebase Phone Auth verification (replaces Twilio OTP for Jamaican numbers) ──
app.post('/api/auth/firebase-verify', async (req, res) => {
  const { idToken, phone, role = 'victim' } = req.body;
  if (!idToken || !phone) {
    return res.status(400).json({ error: 'idToken and phone required' });
  }

  try {
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      const serviceAccount = require('./serviceAccount.json');
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }

    // Verify the Firebase ID token
    const decoded = await admin.auth().verifyIdToken(idToken);
    const firebasePhone = decoded.phone_number;

    // Ensure the phone from Firebase matches what the client claims
    if (firebasePhone !== phone) {
      return res.status(403).json({ error: 'Phone number mismatch' });
    }

    // Find or create user
    let userResult = await pgPool.query('SELECT * FROM users WHERE phone = $1', [phone]);
    let user;
    if (userResult.rows.length === 0) {
      const newUser = await pgPool.query(
        'INSERT INTO users (phone, role) VALUES ($1, $2) RETURNING *',
        [phone, role]
      );
      user = newUser.rows[0];
    } else {
      user = userResult.rows[0];
    }

    const accessToken = generateAccessToken(user);
    const refreshToken = generateRefreshToken(user);

    await pgPool.query(
      "INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, NOW() + INTERVAL '30 days')",
      [user.id, refreshToken]
    );

    res.json({
      accessToken,
      refreshToken,
      user: { id: user.id, phone: user.phone, role: user.role },
    });
  } catch (err) {
    console.error('❌ Firebase verify error:', err.message);
    res.status(401).json({ error: 'Invalid Firebase token' });
  }
});

app.post('/api/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.sendStatus(401);

  try {
    const payload = jwt.verify(refreshToken, REFRESH_TOKEN_SECRET);
    const stored = await pgPool.query(
      'SELECT token FROM refresh_tokens WHERE user_id = $1 AND expires_at > NOW()',
      [payload.id]
    );

    if (stored.rows.length === 0) return res.sendStatus(403);
    if (refreshToken !== stored.rows[0].token) return res.sendStatus(403);

    const user = await pgPool.query('SELECT * FROM users WHERE id = $1', [payload.id]);
    const newAccessToken = generateAccessToken(user.rows[0]);
    res.json({ accessToken: newAccessToken });
  } catch (err) {
    return res.sendStatus(403);
  }
});

// ── Username / password login (volunteers, responders, coordinators) ──
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  try {
    const result = await pgPool.query('SELECT * FROM users WHERE username = $1', [username]);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid username or password' });
    }

    const user = result.rows[0];
    if (!user.password_hash) {
      return res.status(401).json({ error: 'This account uses OTP login' });
    }

    if (password !== user.password_hash) {
      return res.status(401).json({ error: 'Invalid username or password' });
    }

    const accessToken = generateAccessToken(user);
    const refreshToken = generateRefreshToken(user);

    await pgPool.query(
      "INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, NOW() + INTERVAL '30 days')",
      [user.id, refreshToken]
    );

    res.json({
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        username: user.username,
        phone: user.phone,
        role: user.role,
        skills: user.skills || [],
      },
    });
  } catch (err) {
    console.error('\u274c Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Register new account (volunteers, responders, coordinators) ──
app.post('/api/auth/register', async (req, res) => {
  const { username, password, phone, role, skills } = req.body;
  if (!username || !password || !phone || !role) {
    return res.status(400).json({ error: 'Username, password, phone, and role are required' });
  }

  const allowedRoles = ['volunteer', 'responder', 'coordinator'];
  if (!allowedRoles.includes(role)) {
    return res.status(400).json({ error: 'Invalid role. Use: volunteer, responder, coordinator' });
  }

  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }

  try {
    const existing = await pgPool.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Username already taken' });
    }

    const result = await pgPool.query(
      `INSERT INTO users (username, password_hash, phone, role, skills)
       VALUES ($1, $2, $3, $4, $5::jsonb) RETURNING *`,
      [username, password, phone, role, JSON.stringify(skills || [])]
    );

    const user = result.rows[0];
    const accessToken = generateAccessToken(user);
    const refreshToken = generateRefreshToken(user);

    await pgPool.query(
      "INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, NOW() + INTERVAL '30 days')",
      [user.id, refreshToken]
    );

    res.status(201).json({
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        username: user.username,
        phone: user.phone,
        role: user.role,
        skills: user.skills || [],
      },
    });
  } catch (err) {
    console.error('\u274c Registration error:', err);
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Username or phone already taken' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// Offline Sync Endpoint
// Processes a batch of queued actions from the Flutter app.
// Each action carries an idempotencyKey to prevent duplicates.
// ============================================================
app.post('/api/sync', authenticateToken, async (req, res) => {
  const { actions } = req.body;

  if (!Array.isArray(actions) || actions.length === 0) {
    return res.status(400).json({ error: 'actions must be a non-empty array' });
  }

  const results = [];

  for (const item of actions) {
    const { idempotencyKey, action, resource, data } = item;

    try {
      // --- Idempotency check ---
      if (idempotencyKey) {
        const existing = await pgPool.query(
          'SELECT response FROM processed_requests WHERE idempotency_key = $1',
          [idempotencyKey]
        );
        if (existing.rows.length > 0) {
          results.push({ idempotencyKey, status: 'duplicate' });
          continue;
        }
      }

      let responsePayload = null;

      // --- Action handlers ---
      if (resource === 'incident' && action === 'CREATE') {
        const { type, lat, lon, severity, description, disasterType, areaId } = data;

        if (!type || lat == null || lon == null || !severity) {
          results.push({
            idempotencyKey,
            status: 'rejected',
            reason: 'Missing required fields: type, lat, lon, severity',
          });
          continue;
        }

        const point = `POINT(${lon} ${lat})`;
        const insertResult = await pgPool.query(
          `INSERT INTO incidents
             (type, location, severity, description, disaster_type, area_id, submitted_by, status, idempotency_key)
           VALUES ($1, ST_GeogFromText($2), $3, $4, $5, $6, $7, 'active', $8)
           RETURNING id, type, status, created_at`,
          [type, point, severity, description || null, disasterType || null, areaId || null, req.user.id, idempotencyKey || null]
        );

        responsePayload = insertResult.rows[0];
        io.to('coordinators').emit('incident:created', responsePayload);

      } else if (resource === 'incident' && action === 'UPDATE_STATUS') {
        const { id, status } = data;

        if (!id || !status) {
          results.push({ idempotencyKey, status: 'rejected', reason: 'Missing id or status' });
          continue;
        }

        const updateResult = await pgPool.query(
          'UPDATE incidents SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING id, status',
          [status, id]
        );

        if (updateResult.rows.length === 0) {
          results.push({ idempotencyKey, status: 'rejected', reason: `Incident ${id} not found` });
          continue;
        }

        responsePayload = updateResult.rows[0];
        io.to(`incident:${id}`).emit('incident:updated', responsePayload);

      } else if (resource === 'incident' && action === 'DELETE') {
        const { id } = data;

        if (!id) {
          results.push({ idempotencyKey, status: 'rejected', reason: 'Missing incident id' });
          continue;
        }

        await pgPool.query('DELETE FROM incidents WHERE id = $1', [id]);
        responsePayload = { id, deleted: true };

      } else {
        results.push({
          idempotencyKey,
          status: 'rejected',
          reason: `Unsupported resource/action: ${resource}/${action}`,
        });
        continue;
      }

      // --- Record idempotency so replays return 'duplicate' ---
      if (idempotencyKey) {
        await pgPool.query(
          'INSERT INTO processed_requests (idempotency_key, response) VALUES ($1, $2) ON CONFLICT DO NOTHING',
          [idempotencyKey, JSON.stringify(responsePayload)]
        );
      }

      results.push({ idempotencyKey, status: 'applied', ...responsePayload });
    } catch (err) {
      console.error(`❌ Sync error for key ${idempotencyKey}:`, err.message);
      results.push({ idempotencyKey, status: 'rejected', reason: err.message });
    }
  }

  const rejected = results.filter(r => r.status === 'rejected');
  console.log(`✅ Sync processed ${actions.length} action(s): ${results.filter(r => r.status === 'applied').length} applied, ${results.filter(r => r.status === 'duplicate').length} duplicate, ${rejected.length} rejected`);
  if (rejected.length > 0) {
    rejected.forEach(r => console.log(`   ❌ Rejected ${r.idempotencyKey}: ${r.reason}`));
  }
  res.json({ results });
});

// ============================================================
// Incident Management Endpoints
// ============================================================
app.post('/api/incidents', authenticateToken, async (req, res) => {
  const { type, lat, lon, severity, description, disasterType, areaId, idempotencyKey } = req.body;

  if (!type || lat == null || lon == null || !severity) {
    return res.status(400).json({ error: 'Missing required fields: type, lat, lon, severity' });
  }

  // Idempotency check (for direct online submissions)
  if (idempotencyKey) {
    const existing = await pgPool.query(
      'SELECT response FROM processed_requests WHERE idempotency_key = $1',
      [idempotencyKey]
    );
    if (existing.rows.length > 0) {
      return res.status(200).json(existing.rows[0].response);
    }
  }

  const point = `POINT(${lon} ${lat})`;
  const result = await pgPool.query(
    `INSERT INTO incidents (type, location, severity, description, disaster_type, area_id, submitted_by, idempotency_key)
     VALUES ($1, ST_GeogFromText($2), $3, $4, $5, $6, $7, $8) RETURNING *`,
    [type, point, severity, description, disasterType, areaId, req.user.id, idempotencyKey || null]
  );
  const newIncident = result.rows[0];

  io.to('coordinators').emit('incident:created', newIncident);

  if (idempotencyKey) {
    await pgPool.query(
      'INSERT INTO processed_requests (idempotency_key, response) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [idempotencyKey, JSON.stringify(newIncident)]
    );
  }

  res.status(201).json(newIncident);
});

app.get('/api/incidents', authenticateToken, async (req, res) => {
  try {
    const userRole = req.user?.role;
    const userId = req.user?.id;

    const requestedLimit = parseInt(req.query.limit, 10);
    const requestedOffset = parseInt(req.query.offset, 10);
    const status = typeof req.query.status === 'string' ? req.query.status.trim() : '';

    const validStatuses = new Set(['active', 'assigned', 'in-progress', 'resolved']);
    const limit = Number.isFinite(requestedLimit)
      ? Math.min(Math.max(requestedLimit, 1), 500)
      : 500;
    const offset = Number.isFinite(requestedOffset)
      ? Math.max(requestedOffset, 0)
      : 0;

    const conditions = [];
    const params = [];
    const pushParam = (value) => {
      params.push(value);
      return `$${params.length}`;
    };

    if (status && validStatuses.has(status)) {
      conditions.push(`i.status = ${pushParam(status)}`);
    }

    if (userRole === 'victim') {
      if (!userId) {
        return res.status(401).json({ error: 'Unauthenticated user context' });
      }
      conditions.push(`i.submitted_by = ${pushParam(userId)}`);
    } else if (userRole === 'volunteer' || userRole === 'responder') {
      if (!userId) {
        return res.status(401).json({ error: 'Unauthenticated user context' });
      }

      const userRef = pushParam(userId);
      conditions.push(
        `(i.status IN ('active', 'in-progress') OR i.assigned_to = ${userRef} OR i.submitted_by = ${userRef})`
      );
    } else if (userRole !== 'coordinator' && userRole !== 'admin') {
      return res.status(403).json({ error: 'Role not authorized for incident list' });
    }

    const whereClause = conditions.length > 0
      ? `WHERE ${conditions.join(' AND ')}`
      : '';

    const limitParam = pushParam(limit);
    const offsetParam = pushParam(offset);

    const incidents = await pgPool.query(
      `SELECT
         i.id,
         i.type,
         ST_X(i.location::geometry) as lon,
         ST_Y(i.location::geometry) as lat,
         COALESCE(i.severity, 1) as severity,
         i.description,
         COALESCE(i.disaster_type, 'other') as "disasterType",
         COALESCE(i.area_id, 'unknown') as "areaId",
         i.status,
         i.created_at as "timestamp",
         i.updated_at as "lastUpdated",
         i.submitted_by as "submittedBy",
         i.assigned_to as "assignedTo",
         victim.phone as "victimPhone",
         victim.username as "victimName",
         responder.phone as "responderPhone",
         responder.username as "responderName"
       FROM incidents i
       LEFT JOIN users victim ON i.submitted_by = victim.id
       LEFT JOIN users responder ON i.assigned_to = responder.id
       ${whereClause}
       ORDER BY i.created_at DESC
       LIMIT ${limitParam}
       OFFSET ${offsetParam}`,
      params
    );

    res.json(incidents.rows);
  } catch (err) {
    console.error('❌ Incidents list error:', err.message);
    res.status(500).json({ error: 'Failed to fetch incidents' });
  }
});

// ============================================================
// Geospatial Queries (must be before /api/incidents/:id to avoid param clash)
// ============================================================
app.get('/api/incidents/nearby', async (req, res) => {
  const { lat, lon, radius = 5000 } = req.query;
  const point = `POINT(${lon} ${lat})`;
  const incidents = await pgPool.query(
    `SELECT *, ST_Distance(location, ST_GeogFromText($1)) AS distance
     FROM incidents
     WHERE ST_DWithin(location, ST_GeogFromText($1), $2)
     ORDER BY distance`,
    [point, radius]
  );
  res.json(incidents.rows);
});

// Recommended tasks for a volunteer — nearby active incidents sorted by
// severity (highest first), then distance (nearest first).
app.get('/api/incidents/recommended', authenticateToken, authorize('volunteer', 'responder', 'coordinator', 'admin'), async (req, res) => {
  try {
    const { lat, lon, radius = 30000 } = req.query;
    if (!lat || !lon) {
      return res.status(400).json({ error: 'lat and lon are required' });
    }
    const point = `POINT(${lon} ${lat})`;
    const result = await pgPool.query(
      `SELECT
         id,
         type,
         ST_X(location::geometry) as lon,
         ST_Y(location::geometry) as lat,
         COALESCE(severity, 1) as severity,
         description,
         COALESCE(disaster_type, 'other') as "disasterType",
         COALESCE(area_id, 'unknown') as "areaId",
         status,
         created_at as "timestamp",
         updated_at as "lastUpdated",
         people_affected as "peopleAffected",
         assigned_to as "assignedTo",
         ST_Distance(location, ST_GeogFromText($1)) AS distance
       FROM incidents
       WHERE status = 'active'
         AND ST_DWithin(location, ST_GeogFromText($1), $2)
       ORDER BY severity DESC, ST_Distance(location, ST_GeogFromText($1)) ASC
       LIMIT 50`,
      [point, radius]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('❌ Recommended incidents error:', err.message);
    res.status(500).json({ error: 'Failed to fetch recommended incidents' });
  }
});

app.get('/api/incidents/heatmap', async (req, res) => {
  const { bbox, resolution = 0.01 } = req.query;
  const result = await pgPool.query(
    `SELECT ST_AsGeoJSON(ST_Centroid(ST_SnapToGrid(location, $1))) as cell,
            COUNT(*) as count
     FROM incidents
     WHERE location && ST_MakeEnvelope($2, $3, $4, $5, 4326)
     GROUP BY cell`,
    [resolution, ...bbox.split(',')]
  );
  res.json(result.rows);
});

app.get('/api/incidents/:id', async (req, res) => {
  const id = parseInt(req.params.id);
  const incident = await pgPool.query('SELECT * FROM incidents WHERE id = $1', [id]);
  if (incident.rows.length === 0) return res.status(404).json({ error: 'Not found' });
  res.json(incident.rows[0]);
});

app.patch('/api/incidents/:id', authenticateToken, async (req, res) => {
  const id = parseInt(req.params.id);
  const { status } = req.body;
  const result = await pgPool.query(
    'UPDATE incidents SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
    [status, id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
  const updated = result.rows[0];
  io.to(`incident:${id}`).emit('incident:updated', updated);
  res.json(updated);
});

app.patch('/api/incidents/bulk', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const { ids, status } = req.body;
  await pgPool.query(
    'UPDATE incidents SET status = $1, updated_at = NOW() WHERE id = ANY($2)',
    [status, ids]
  );
  res.json({ message: 'Updated' });
});

// ============================================================
// Resources
// ============================================================
app.get('/api/resources', async (req, res) => {
  const resources = await pgPool.query('SELECT * FROM resources ORDER BY last_updated DESC');
  res.json(resources.rows);
});

app.post('/api/resources', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const { type, quantity, unit, lat, lon, organisation_id } = req.body;
  const point = `POINT(${lon} ${lat})`;
  const result = await pgPool.query(
    'INSERT INTO resources (type, quantity, unit, location, organisation_id) VALUES ($1, $2, $3, ST_GeogFromText($4), $5) RETURNING *',
    [type, quantity, unit, point, organisation_id]
  );
  const newResource = result.rows[0];
  io.emit('resource:created', newResource);
  res.status(201).json(newResource);
});

app.patch('/api/resources/:id/allocate', authenticateToken, async (req, res) => {
  const { incident_id, quantity } = req.body;
  const resourceId = req.params.id;

  await pgPool.query(
    'UPDATE resources SET quantity = quantity - $1 WHERE id = $2 AND quantity >= $1',
    [quantity, resourceId]
  );
  await pgPool.query(
    'INSERT INTO resource_allocations (resource_id, incident_id, quantity) VALUES ($1, $2, $3)',
    [resourceId, incident_id, quantity]
  );

  res.json({ message: 'Allocated' });
});

// ============================================================
// Stats
// ============================================================
app.get('/api/stats', async (req, res) => {
  const total = await pgPool.query('SELECT COUNT(*) FROM incidents');
  const active = await pgPool.query("SELECT COUNT(*) FROM incidents WHERE status = 'active'");
  const resolved = await pgPool.query("SELECT COUNT(*) FROM incidents WHERE status = 'resolved'");
  const byType = await pgPool.query('SELECT type, COUNT(*) FROM incidents GROUP BY type');
  const bySeverity = await pgPool.query('SELECT severity, COUNT(*) FROM incidents GROUP BY severity');

  res.json({
    totalIncidents: parseInt(total.rows[0].count),
    activeIncidents: parseInt(active.rows[0].count),
    resolvedIncidents: parseInt(resolved.rows[0].count),
    byType: Object.fromEntries(byType.rows.map(r => [r.type, parseInt(r.count)])),
    bySeverity: {
      critical: bySeverity.rows.filter(r => r.severity >= 4).reduce((sum, r) => sum + parseInt(r.count), 0),
      moderate: bySeverity.rows.filter(r => r.severity >= 2 && r.severity <= 3).reduce((sum, r) => sum + parseInt(r.count), 0),
      low: bySeverity.rows.filter(r => r.severity === 1).reduce((sum, r) => sum + parseInt(r.count), 0),
    },
  });
});

// ============================================================
// Area Analysis
// ============================================================
const DISASTER_TYPE_WEIGHTS = {
  hurricane: 1.2,
  earthquake: 1.5,
  flood: 1.1,
  fire: 1.3,
  tornado: 1.4,
  other: 1.0,
};

function computeAreaSeverity(incidentList) {
  if (!incidentList || incidentList.length === 0) return 0;
  const totalWeightedSeverity = incidentList.reduce((sum, inc) => {
    const weight = DISASTER_TYPE_WEIGHTS[inc.disaster_type] || 1.0;
    return sum + inc.severity * weight;
  }, 0);
  const multiplier = 1 + Math.log(incidentList.length);
  return totalWeightedSeverity * multiplier;
}

app.get('/api/severity/:areaId', async (req, res) => {
  const { areaId } = req.params;
  const areaIncidents = await pgPool.query('SELECT * FROM incidents WHERE area_id = $1', [areaId]);
  const severityScore = computeAreaSeverity(areaIncidents.rows);
  res.json({ areaId, severityScore, incidentCount: areaIncidents.rows.length });
});

app.get('/api/resources/estimate/:areaId', async (req, res) => {
  const { areaId } = req.params;
  res.json({
    areaId,
    needed: { water: 500, food: 200, medical: 50, shelter: 10, rescue_team: 5 },
  });
});

// ============================================================
// SMS Fallback Reporting (#10) — Vonage Inbound Webhook
// ============================================================
app.post('/api/sms/incoming', async (req, res) => {
  // Vonage sends: { msisdn, to, text, ... } (GET or POST)
  const text = (req.body.text || req.body.Body || req.query.text || '').trim();
  const phone = req.body.msisdn || req.body.From || req.query.msisdn || '';

  // Parse: HELP TYPE LOCATION [N people]
  const match = text.match(
    /^(HELP|SOS)\s*(MEDICAL|TRAPPED|SUPPLIES|SHELTER|FIRE|FLOOD)?\s*(.*?)(?:\s+(\d+)\s*(?:people|persons|ppl))?$/i
  );

  if (!match) {
    // Send structured prompt back via SMS
    await sendSMS(phone, 'To report an emergency, text: HELP [TYPE] [LOCATION] [N people]\nTypes: MEDICAL, TRAPPED, SUPPLIES, SHELTER, FIRE, FLOOD\nExample: HELP MEDICAL 14 Palm Street 3 people');
    return res.json({ status: 'prompt_sent' });
  }

  const type = (match[2] || 'other').toLowerCase();
  const locationText = (match[3] || '').trim() || 'Unknown location';
  const peopleAffected = match[4] ? parseInt(match[4]) : 1;

  // Attempt geocoding, fallback to default Kingston coordinates
  const geo = await geocodeAddress(locationText);
  const lat = geo ? geo.lat : 18.1096;
  const lon = geo ? geo.lon : -77.2975;

  const refNumber = `SMS-${Date.now().toString(36).toUpperCase()}`;

  try {
    // Find or create user by phone
    let userResult = await pgPool.query('SELECT id FROM users WHERE phone = $1', [phone]);
    if (userResult.rows.length === 0) {
      userResult = await pgPool.query(
        "INSERT INTO users (phone, role) VALUES ($1, 'victim') RETURNING id",
        [phone]
      );
    }
    const userId = userResult.rows[0].id;

    // Create incident
    const point = `POINT(${lon} ${lat})`;
    const result = await pgPool.query(
      `INSERT INTO incidents (type, location, severity, description, area_id, status, submitted_by, people_affected, reference_number, source, source_phone)
       VALUES ($1, ST_GeogFromText($2), $3, $4, $5, 'active', $6, $7, $8, 'sms', $9) RETURNING *`,
      [type, point, 3, `SMS report: ${locationText}`, locationText, userId, peopleAffected, refNumber, phone]
    );

    const incident = result.rows[0];
    io.emit('incident:created', incident);
    console.log(`📱 [SMS] Incident ${refNumber} created from ${phone}: ${type} at ${locationText} (${lat},${lon})`);

    await sendSMS(phone, `Your emergency has been reported.\nReference: ${refNumber}\nType: ${type.toUpperCase()}\nWe will send updates to this number.`);
    res.json({ status: 'incident_created', refNumber });
  } catch (err) {
    console.error('❌ [SMS] Error processing incoming SMS:', err);
    await sendSMS(phone, 'Error processing your request. Please try again or call emergency services.');
    res.status(500).json({ error: 'Processing failed' });
  }
});

// ============================================================
// Incident Resource Estimation Logic
// ============================================================
function estimateIncidentResources(incident) {
  // Example logic: can be replaced with more sophisticated estimation
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
  // Scale by people affected and severity
  const needs = {};
  for (const k in baseNeeds) {
    needs[k] = Math.ceil(baseNeeds[k] * people * (0.5 + 0.25 * severity));
  }
  return needs;
}

// Attach resource needs to incident on creation
// const oldIncidentInsert = pgPool.query;
// pgPool.query = async function(sql, ...args) {
//   // Intercept only incident creation
//   if (typeof sql === 'string' && sql.trim().toLowerCase().startsWith('insert into incidents')) {
//     // Try to extract incident fields from args
//     const params = args[0] || [];
//     // crude: type, location, severity, description, area_id, status, submitted_by, people_affected, reference_number, source, source_phone
//     const incident = {
//       type: params[0],
//       severity: params[2],
//       people_affected: params[6],
//     };
//     const needs = estimateIncidentResources(incident);
//     // Add as JSONB column if exists, else ignore
//     if (sql.includes('resource_needs')) {
//       // Insert needs as JSONB
//       const idx = sql.split(',').findIndex(s => s.includes('resource_needs'));
//       if (idx >= 0) {
//         params[idx] = needs;
//       }
//     }
//   }
//   return oldIncidentInsert.apply(this, [sql, ...args]);
// };  CHECK THIS AS SOON 

// Endpoint: Get estimated resource needs for an incident
app.get('/api/incidents/:id/resource-needs', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const result = await pgPool.query('SELECT * FROM incidents WHERE id = $1', [incidentId]);
  if (result.rows.length === 0) return res.status(404).json({ error: 'Incident not found' });
  const incident = result.rows[0];
  // If resource_needs column exists, use it; else estimate on the fly
  let needs = incident.resource_needs;
  if (!needs) {
    needs = estimateIncidentResources(incident);
  }
  res.json({ incidentId, resourceNeeds: needs });
});

// ...existing code...
// ============================================================
app.patch('/api/incidents/:id/transition', async (req, res) => {
  const id = parseInt(req.params.id);
  const { status: newStatus } = req.body;

  try {
    const current = await pgPool.query(
      'SELECT status, submitted_by, reference_number, source_phone FROM incidents WHERE id = $1',
      [id]
    );
    if (current.rows.length === 0) return res.status(404).json({ error: 'Not found' });

    const fromStatus = current.rows[0].status;

    await pgPool.query('UPDATE incidents SET status = $1, updated_at = NOW() WHERE id = $2', [newStatus, id]);

    // Log history
    await pgPool.query(
      'INSERT INTO incident_history (incident_id, from_status, to_status, changed_by) VALUES ($1, $2, $3, $4)',
      [id, fromStatus, newStatus, req.user.id]
    );

    // Notify via WebSocket
    io.to(`incident:${id}`).emit('incident:updated', { id, status: newStatus });
    io.to('coordinators').emit('incident:updated', { id, status: newStatus });

    // SMS notification for SMS-originated incidents
    if (current.rows[0].source_phone) {
      const ref = current.rows[0].reference_number || id;
      const statusMessages = {
        'assigned': `Update for ${ref}: A volunteer has been assigned to help you.`,
        'in-progress': `Update for ${ref}: Help is on the way to your location.`,
        'resolved': `Update for ${ref}: Your request has been resolved. Stay safe.`,
      };
      if (statusMessages[newStatus]) {
        sendSMS(current.rows[0].source_phone, statusMessages[newStatus]).catch(err =>
          console.error('❌ [SMS] Failed to send status update:', err)
        );
      }
    }

    // Insert system message into chat
    const systemContent = {
      'assigned': 'A volunteer has been assigned to this incident.',
      'in-progress': 'Help is en route.',
      'resolved': 'This incident has been resolved.',
    };
    if (systemContent[newStatus]) {
      await pgPool.query(
        `INSERT INTO messages (incident_id, sender_id, content, message_type) VALUES ($1, $2, $3, 'system')`,
        [id, req.user.id, systemContent[newStatus]]
      );
      io.to(`incident:${id}`).emit('chat:message', {
        incident_id: id,
        sender_id: req.user.id,
        content: systemContent[newStatus],
        message_type: 'system',
        created_at: new Date().toISOString(),
      });
    }

    res.json({ id, fromStatus, toStatus: newStatus });
  } catch (err) {
    console.error('❌ Transition error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// User Location Updates (for volunteer proximity)
// ============================================================
app.patch('/api/users/:id/location', async (req, res) => {
  const userId = parseInt(req.params.id);
  const { lat, lon, latitude, longitude } = req.body;
  const finalLat = lat ?? latitude;
  const finalLon = lon ?? longitude;
  if (finalLat == null || finalLon == null || isNaN(finalLat) || isNaN(finalLon)) {
    return res.status(400).json({ error: 'lat and lon are required and must be numbers' });
  }
  await pgPool.query(
    'UPDATE users SET last_lat = $1, last_lon = $2, last_location_at = NOW(), location = ST_GeogFromText($3) WHERE id = $4',
    [finalLat, finalLon, `POINT(${finalLon} ${finalLat})`, userId]
  );
  io.to('coordinators').emit('user:location', { userId, lat: finalLat, lon: finalLon });
  res.json({ status: 'ok' });
});

// GET /api/users/me/location — current user's saved location anchor and check-in state
app.get('/api/users/me/location', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT id, role,
              last_lat, last_lon, last_location_at,
              active_location_lat, active_location_lon, active_location_name,
              checked_in_at, check_in_station_name, check_in_station_parish,
              check_in_station_lat, check_in_station_lon
       FROM users
       WHERE id = $1`,
      [req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error('❌ Current user location fetch error:', err.message);
    res.status(500).json({ error: 'Failed to fetch current user location' });
  }
});

// PATCH /api/users/me/check-in — one-tap volunteer check-in at selected police station
app.patch('/api/users/me/check-in', authenticateToken, authorize('volunteer'), async (req, res) => {
  try {
    const { stationName, parish, lat, lon } = req.body;

    const parsedLat = Number(lat);
    const parsedLon = Number(lon);
    if (!stationName || !parish || Number.isNaN(parsedLat) || Number.isNaN(parsedLon)) {
      return res.status(400).json({
        error: 'stationName, parish, lat, and lon are required',
      });
    }

    const result = await pgPool.query(
      `UPDATE users
       SET checked_in_at = NOW(),
           check_in_station_name = $1,
           check_in_station_parish = $2,
           check_in_station_lat = $3,
           check_in_station_lon = $4
       WHERE id = $5
       RETURNING id, checked_in_at, check_in_station_name, check_in_station_parish,
                 check_in_station_lat, check_in_station_lon`,
      [stationName.trim(), parish.trim(), parsedLat, parsedLon, req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const payload = result.rows[0];
    io.to('coordinators').emit('volunteer:checked-in', {
      userId: payload.id,
      stationName: payload.check_in_station_name,
      parish: payload.check_in_station_parish,
      checkedInAt: payload.checked_in_at,
    });

    res.json({ status: 'checked_in', ...payload });
  } catch (err) {
    console.error('❌ Volunteer check-in update error:', err.message);
    res.status(500).json({ error: 'Failed to save volunteer check-in' });
  }
});

// GET /api/users/:id/proximity — Approximate location (500m accuracy)
app.get('/api/users/:id/proximity', async (req, res) => {
  const userId = parseInt(req.params.id);
  const result = await pgPool.query(
    'SELECT last_lat, last_lon, last_location_at FROM users WHERE id = $1',
    [userId]
  );
  if (result.rows.length === 0 || !result.rows[0].last_lat) {
    return res.json({ available: false });
  }
  const row = result.rows[0];
  const offset = 0.0045; // ~500m fuzzing
  res.json({
    available: true,
    lat: row.last_lat + (Math.random() - 0.5) * offset,
    lon: row.last_lon + (Math.random() - 0.5) * offset,
    lastUpdated: row.last_location_at,
  });
});

// ============================================================
// User Profile Updates (Volunteer Profile #Volunteer-Profile)
// ============================================================
app.patch('/api/users/:id/profile', async (req, res) => {
  const userId = parseInt(req.params.id);
  const { skills, vehicle, availability, languages, resources,
          active_location_lat, active_location_lon, active_location_name } = req.body;

  const updates = [];
  const values = [];
  let paramIndex = 1;

  if (skills !== undefined) {
    updates.push(`skills = $${paramIndex++}`);
    values.push(JSON.stringify(skills));
  }
  if (vehicle !== undefined) {
    updates.push(`vehicle = $${paramIndex++}`);
    values.push(vehicle);
  }
  if (availability !== undefined) {
    updates.push(`availability = $${paramIndex++}`);
    values.push(availability);
  }
  if (languages !== undefined) {
    updates.push(`languages = $${paramIndex++}`);
    values.push(JSON.stringify(languages));
  }
  if (active_location_lat !== undefined) {
    updates.push(`active_location_lat = $${paramIndex++}`);
    values.push(active_location_lat);
  }
  if (active_location_lon !== undefined) {
    updates.push(`active_location_lon = $${paramIndex++}`);
    values.push(active_location_lon);
  }
  if (active_location_name !== undefined) {
    updates.push(`active_location_name = $${paramIndex++}`);
    values.push(active_location_name);
  }

  if (updates.length === 0) {
    return res.status(400).json({ error: 'No fields to update' });
  }

  values.push(userId);
  await pgPool.query(
    `UPDATE users SET ${updates.join(', ')} WHERE id = $${paramIndex}`,
    values
  );
  res.json({ status: 'updated' });
});

app.get('/api/users/:id/profile', async (req, res) => {
  const userId = parseInt(req.params.id);
  const result = await pgPool.query(
    `SELECT id, phone, role, skills, vehicle, availability, languages,
            active_location_lat, active_location_lon, active_location_name,
            checked_in_at, check_in_station_name, check_in_station_parish,
            check_in_station_lat, check_in_station_lon
     FROM users WHERE id = $1`,
    [userId]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
  res.json(result.rows[0]);
});

// PATCH /api/users/:id/availability — Quick toggle
app.patch('/api/users/:id/availability', async (req, res) => {
  const userId = parseInt(req.params.id);
  const { availability } = req.body;
  const validStatuses = ['available', 'unavailable', 'on_task'];
  if (!validStatuses.includes(availability)) {
    return res.status(400).json({ error: 'Invalid availability. Use: available, unavailable, on_task' });
  }
  await pgPool.query('UPDATE users SET availability = $1 WHERE id = $2', [availability, userId]);
  res.json({ status: 'updated', availability });
});

// ============================================================
// Broadcast Alerts (#13)
// ============================================================
app.post('/api/broadcasts', async (req, res) => {
  const { message, targetRoles, expiresInHours } = req.body;
  if (!message) return res.status(400).json({ error: 'message required' });

  const expiresAt = expiresInHours
    ? new Date(Date.now() + expiresInHours * 60 * 60 * 1000).toISOString()
    : null;

  const result = await pgPool.query(
    `INSERT INTO broadcast_alerts (message, target_roles, expires_at, created_by)
     VALUES ($1, $2, $3, $4) RETURNING *`,
    [message, targetRoles || 'all', expiresAt, req.user.id]
  );
  const alert = result.rows[0];

  // Fan out via WebSocket
  const targetRoom = targetRoles === 'volunteers' ? 'volunteers' : null;
  if (targetRoom) {
    io.to(targetRoom).emit('broadcast:alert', alert);
  } else {
    io.emit('broadcast:alert', alert);
  }
  console.log(`📢 [Broadcast] Alert #${alert.id}: "${message.substring(0, 50)}..."`);
  res.status(201).json(alert);
});

app.get('/api/broadcasts', async (req, res) => {
  const result = await pgPool.query(
    `SELECT * FROM broadcast_alerts
     WHERE (expires_at IS NULL OR expires_at > NOW())
     ORDER BY created_at DESC LIMIT 50`
  );
  res.json(result.rows);
});

app.post('/api/broadcasts/:id/acknowledge', async (req, res) => {
  const alertId = parseInt(req.params.id);
  const userId = req.user.id;
  await pgPool.query(
    `INSERT INTO user_alerts (user_id, alert_id, acknowledged, acknowledged_at, delivered_via)
     VALUES ($1, $2, TRUE, NOW(), 'push')
     ON CONFLICT DO NOTHING`,
    [userId, alertId]
  );
  res.json({ status: 'acknowledged' });
});

// ============================================================
// Volunteer Stats / Gamification (#3)
// ============================================================
app.get('/api/volunteers/:id/stats', async (req, res) => {
  try {
    const userId = parseInt(req.params.id);
    // Ensure the user exists before inserting into volunteer_stats
    const userCheck = await pgPool.query('SELECT id FROM users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    await pgPool.query(
      'INSERT INTO volunteer_stats (user_id) VALUES ($1) ON CONFLICT DO NOTHING',
      [userId]
    );
    const result = await pgPool.query('SELECT * FROM volunteer_stats WHERE user_id = $1', [userId]);
    const stats = result.rows[0];

    const resolved = await pgPool.query(
      "SELECT COUNT(*) as count FROM incidents WHERE assigned_to = $1 AND status = 'resolved'",
      [userId]
    );

    const active = await pgPool.query(
      "SELECT COUNT(*) as count FROM incidents WHERE assigned_to = $1 AND status IN ('active', 'in-progress')",
      [userId]
    );

    res.json({
      ...stats,
      tasks_completed: parseInt(resolved.rows[0].count),
      active_tasks: parseInt(active.rows[0].count),
      tasks_from_incidents: parseInt(resolved.rows[0].count),
    });
  } catch (err) {
    console.error('❌ getVolunteerStats error:', err.message);
    res.status(500).json({ error: 'Failed to fetch volunteer stats' });
  }
});

app.post('/api/volunteers/:id/complete-task', async (req, res) => {
  try {
    const userId = parseInt(req.params.id);
    const { hoursSpent, taskType } = req.body;

    const userCheck = await pgPool.query('SELECT id FROM users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    await pgPool.query(
      'INSERT INTO volunteer_stats (user_id) VALUES ($1) ON CONFLICT DO NOTHING',
      [userId]
    );

    await pgPool.query(
      `UPDATE volunteer_stats
       SET tasks_completed = tasks_completed + 1,
           hours_contributed = hours_contributed + $1,
           last_active_at = NOW(),
           updated_at = NOW()
       WHERE user_id = $2`,
      [hoursSpent || 1, userId]
    );

    // Check and award badges
    const stats = await pgPool.query('SELECT * FROM volunteer_stats WHERE user_id = $1', [userId]);
    const s = stats.rows[0];
    const currentBadges = s.badges || [];
    const newBadges = [...currentBadges];

    if (s.tasks_completed >= 1 && !currentBadges.includes('First Responder')) newBadges.push('First Responder');
    if (s.tasks_completed >= 10 && !currentBadges.includes('Seasoned Helper')) newBadges.push('Seasoned Helper');
    if (s.tasks_completed >= 50 && !currentBadges.includes('Veteran Volunteer')) newBadges.push('Veteran Volunteer');
    if (s.hours_contributed >= 100 && !currentBadges.includes('100 Hours')) newBadges.push('100 Hours');
    if (taskType === 'medical_emergency' && !currentBadges.includes('Medical Specialist')) newBadges.push('Medical Specialist');

    if (newBadges.length > currentBadges.length) {
      await pgPool.query('UPDATE volunteer_stats SET badges = $1 WHERE user_id = $2', [JSON.stringify(newBadges), userId]);
    }

    res.json({ status: 'recorded', stats: { ...s, badges: newBadges } });
  } catch (err) {
    console.error('❌ completeTask error:', err.message);
    res.status(500).json({ error: 'Failed to complete task' });
  }
});

app.get('/api/volunteers/leaderboard', async (req, res) => {
  const result = await pgPool.query(
    `SELECT vs.user_id, vs.tasks_completed, vs.hours_contributed, vs.badges
     FROM volunteer_stats vs
     WHERE vs.last_active_at > NOW() - INTERVAL '30 days'
     ORDER BY vs.tasks_completed DESC, vs.hours_contributed DESC
     LIMIT 20`
  );
  const leaderboard = result.rows.map((r, i) => ({
    rank: i + 1,
    userId: r.user_id,
    tasksCompleted: r.tasks_completed,
    hoursContributed: parseFloat(r.hours_contributed),
    badges: r.badges || [],
  }));
  res.json(leaderboard);
});

// ============================================================
// Matching Engine — Volunteer → Incident by skills, distance, availability
// ============================================================
app.get('/api/incidents/:id/match', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const maxDistance = parseInt(req.query.maxDistance) || 20000; // default 20km

  try {
    const incident = await pgPool.query(
      'SELECT *, ST_X(location::geometry) as lon, ST_Y(location::geometry) as lat FROM incidents WHERE id = $1',
      [incidentId]
    );
    if (incident.rows.length === 0) return res.status(404).json({ error: 'Incident not found' });

    const inc = incident.rows[0];
    const incType = inc.type;

    // Skill mapping: incident type → relevant skills
    const skillMap = {
      medical: ['First Aid/CPR', 'Medical Professional', 'Basic Life Support', 'Emergency Medicine'],
      fire: ['Firefighting', 'Hazmat', 'Search & Rescue'],
      flood: ['Swift Water Rescue', 'Flood Response', 'Heavy Equipment'],
      trapped: ['Search & Rescue', 'Heavy Equipment', 'Structural Assessment'],
      supplies: ['Logistics', 'Supply Chain', 'Transport'],
      shelter: ['Logistics', 'Mental Health', 'Crisis Counseling'],
    };

    const relevantSkills = skillMap[incType] || [];

    // Get estimated resource needs for this incident
    let resourceNeeds = inc.resource_needs;
    if (!resourceNeeds) {
      resourceNeeds = estimateIncidentResources(inc);
    }

    // Find available volunteers/responders within range, ordered by skill match + distance
    const candidates = await pgPool.query(
      `SELECT u.id, u.phone, u.role, u.skills, u.vehicle, u.availability,
              u.last_lat, u.last_lon,
              ST_Distance(u.location, ST_GeogFromText($1)) as distance
       FROM users u
       WHERE u.role IN ('volunteer', 'responder')
         AND u.availability = 'available'
         AND u.last_lat IS NOT NULL
         AND ST_DWithin(u.location, ST_GeogFromText($1), $2)
       ORDER BY distance ASC
       LIMIT 20`,
      [`POINT(${inc.lon} ${inc.lat})`, maxDistance]
    );

    // For each candidate, check if they have access to required resources
    // For now, assume resources are globally available (future: link to user/org)
    const resourcesResult = await pgPool.query('SELECT * FROM resources WHERE status = $1', ['available']);
    const availableResources = resourcesResult.rows;

    const scored = candidates.rows.map(c => {
      const userSkills = c.skills || [];
      const skillMatch = relevantSkills.filter(s =>
        userSkills.some(us => us.toLowerCase().includes(s.toLowerCase()))
      ).length;

      // Resource fulfillment: count how many needed resources are available
      let resourceFulfillment = 0;
      let resourceGap = 0;
      for (const [rtype, neededQty] of Object.entries(resourceNeeds)) {
        const totalAvailable = availableResources
          .filter(r => r.type.toLowerCase() === rtype.toLowerCase())
          .reduce((sum, r) => sum + (r.quantity || 0), 0);
        if (totalAvailable >= neededQty) resourceFulfillment++;
        else resourceGap++;
      }

      // Prioritization score: skills, proximity, resource fulfillment
      return {
        userId: c.id,
        phone: c.phone,
        role: c.role,
        skills: c.skills,
        vehicle: c.vehicle,
        distance: Math.round(c.distance),
        skillMatch,
        resourceFulfillment,
        resourceGap,
        score:
          skillMatch * 1000 +
          (maxDistance - Math.min(c.distance, maxDistance)) +
          resourceFulfillment * 500 -
          resourceGap * 200,
      };
    });

    scored.sort((a, b) => b.score - a.score);

    res.json({ incidentId, incidentType: incType, resourceNeeds, candidates: scored });
  } catch (err) {
    console.error('❌ Matching engine error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// List all volunteers/responders for coordinator assignment (enhanced Ph1+3)
app.get('/api/volunteers/list', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT u.id, u.username, u.phone, u.role, u.availability,
              u.skills, u.vehicle, u.languages, u.last_lat, u.last_lon, u.last_location_at,
              (SELECT COUNT(*) FROM incidents WHERE assigned_to = u.id AND status IN ('active','in-progress')) as active_tasks,
              (SELECT COUNT(*) FROM incidents WHERE assigned_to = u.id AND status = 'resolved') as total_completed
       FROM users u
       WHERE u.role IN ('volunteer', 'responder')
       ORDER BY u.availability ASC, u.username ASC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('❌ Error fetching volunteers:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Assign or reassign a volunteer to an incident (coordinator override)
app.post('/api/incidents/:id/assign', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const { volunteerId, status } = req.body;

  if (!volunteerId) return res.status(400).json({ error: 'volunteerId required' });

  try {
    // Get current incident state
    const current = await pgPool.query('SELECT status, assigned_to FROM incidents WHERE id = $1', [incidentId]);
    if (current.rows.length === 0) return res.status(404).json({ error: 'Incident not found' });

    const prevStatus = current.rows[0].status;
    const prevAssigned = current.rows[0].assigned_to;
    const newStatus = status || 'assigned';

    // Update incident assignment
    await pgPool.query(
      'UPDATE incidents SET assigned_to = $1, status = $2, updated_at = NOW() WHERE id = $3',
      [volunteerId, newStatus, incidentId]
    );

    // Free previous volunteer if reassigning
    if (prevAssigned && prevAssigned !== volunteerId) {
      await pgPool.query(
        "UPDATE users SET availability = 'available' WHERE id = $1",
        [prevAssigned]
      );
    }

    // Update new volunteer availability
    await pgPool.query(
      "UPDATE users SET availability = 'on_task' WHERE id = $1",
      [volunteerId]
    );

    // Allocate resources to the volunteer based on incident needs
    // 1. Get incident resource needs
    const incidentRes = await pgPool.query('SELECT resource_needs FROM incidents WHERE id = $1', [incidentId]);
    const resourceNeeds = incidentRes.rows[0]?.resource_needs || {};
    // 2. For each resource type, allocate from available resources
    for (const [rtype, qty] of Object.entries(resourceNeeds)) {
      if (!qty || qty <= 0) continue;
      // Find available resources of this type
      const resRows = await pgPool.query('SELECT id, quantity FROM resources WHERE type = $1 AND status = $2 AND quantity > 0 ORDER BY quantity DESC', [rtype, 'available']);
      let remaining = qty;
      for (const r of resRows.rows) {
        if (remaining <= 0) break;
        const allocQty = Math.min(r.quantity, remaining);
        // Deduct from resource
        await pgPool.query('UPDATE resources SET quantity = quantity - $1, last_updated = NOW() WHERE id = $2', [allocQty, r.id]);
        // Log allocation
        await pgPool.query('INSERT INTO resource_allocations (resource_id, incident_id, quantity, notes) VALUES ($1, $2, $3, $4)', [r.id, incidentId, allocQty, `Allocated to volunteer ${volunteerId} for incident`]);
        remaining -= allocQty;
      }
    }

    // Log history
    await pgPool.query(
      'INSERT INTO incident_history (incident_id, from_status, to_status, changed_by) VALUES ($1, $2, $3, $4)',
      [incidentId, prevStatus, newStatus, req.user.id]
    );

    // Notify via Socket.io
    io.to(`incident:${incidentId}`).emit('incident:updated', { id: incidentId, status: newStatus, assignedTo: volunteerId });
    io.to('coordinators').emit('incident:updated', { id: incidentId, status: newStatus });

    // Create notification for the volunteer
    await pgPool.query(
      `INSERT INTO notifications (user_id, type, data) VALUES ($1, 'TASK_ASSIGNED', $2)`,
      [volunteerId, JSON.stringify({ incidentId, message: 'You have been assigned a new task' })]
    );

    res.json({ status: 'assigned', incidentId, volunteerId });
  } catch (err) {
    console.error('❌ Assignment error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Chat / Two-Way Messaging per Incident (#9)
// ============================================================
app.get('/api/incidents/:id/messages', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const limit = parseInt(req.query.limit) || 50;
  const before = req.query.before; // ISO timestamp for pagination

  try {
    let query = `SELECT m.*, u.phone as sender_phone, u.role as sender_role
                 FROM messages m
                 LEFT JOIN users u ON m.sender_id = u.id
                 WHERE m.incident_id = $1`;
    const params = [incidentId];

    if (before) {
      query += ` AND m.created_at < $2`;
      params.push(before);
    }

    query += ` ORDER BY m.created_at DESC LIMIT $${params.length + 1}`;
    params.push(limit);

    const result = await pgPool.query(query, params);
    res.json(result.rows.reverse()); // return in chronological order
  } catch (err) {
    console.error('❌ Get messages error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/api/incidents/:id/messages', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const { content, messageType = 'text' } = req.body;

  if (!content || !content.trim()) {
    return res.status(400).json({ error: 'Message content required' });
  }

  try {
    const result = await pgPool.query(
      `INSERT INTO messages (incident_id, sender_id, content, message_type)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [incidentId, req.user.id, content.trim(), messageType]
    );

    const message = result.rows[0];

    // Broadcast to Socket.io room for this incident
    io.to(`incident:${incidentId}`).emit('chat:message', {
      ...message,
      sender_role: req.user.role,
    });

    // Mark other users' messages as delivered
    await pgPool.query(
      `UPDATE messages SET delivered = true WHERE incident_id = $1 AND sender_id != $2 AND delivered = false`,
      [incidentId, req.user.id]
    );

    // Forward chat messages to SMS for SMS-originated incidents
    const incidentRow = await pgPool.query(
      'SELECT source_phone FROM incidents WHERE id = $1 AND source = $2',
      [incidentId, 'sms']
    );
    if (incidentRow.rows.length > 0 && incidentRow.rows[0].source_phone) {
      sendSMS(incidentRow.rows[0].source_phone, `[ReddiHelp] ${content.trim()}`).catch(err =>
        console.error('❌ [SMS] Chat forward failed:', err)
      );
    }

    res.status(201).json(message);
  } catch (err) {
    console.error('❌ Send message error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Mark messages as read
app.patch('/api/incidents/:id/messages/read', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  try {
    await pgPool.query(
      `UPDATE messages SET read = true WHERE incident_id = $1 AND sender_id != $2 AND read = false`,
      [incidentId, req.user.id]
    );
    res.json({ status: 'ok' });
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// Get unread count per incident for a user
app.get('/api/messages/unread', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT incident_id, COUNT(*) as unread_count
       FROM messages
       WHERE sender_id != $1 AND read = false
       GROUP BY incident_id`,
      [req.user.id]
    );
    const counts = {};
    result.rows.forEach(r => { counts[r.incident_id] = parseInt(r.unread_count); });
    res.json(counts);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// Quick-reply templates for coordinators
app.get('/api/chat/templates', authenticateToken, (req, res) => {
  res.json([
    { id: 1, label: 'Help en route', text: 'A volunteer has been dispatched and is on their way to your location.' },
    { id: 2, label: 'ETA update', text: 'Estimated time of arrival is approximately 15 minutes.' },
    { id: 3, label: 'Need more info', text: 'Can you provide more details about your situation? Number of people, specific needs?' },
    { id: 4, label: 'Stay safe', text: 'Please stay in a safe location. Help is being coordinated.' },
    { id: 5, label: 'Evacuation', text: 'Please evacuate to the nearest shelter immediately. Follow posted evacuation routes.' },
    { id: 6, label: 'Resources coming', text: 'Resources (water, food, medical supplies) are being sent to your area.' },
    { id: 7, label: 'Resolved', text: 'Your request has been resolved. Please let us know if you need further assistance.' },
  ]);
});

// ============================================================
// FCM Device Token Registration & Notification Service (#5)
// ============================================================
app.post('/api/devices/register', authenticateToken, async (req, res) => {
  const { fcmToken, platform } = req.body;
  if (!fcmToken) return res.status(400).json({ error: 'fcmToken required' });

  try {
    await pgPool.query(
      `INSERT INTO device_tokens (user_id, token, platform, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id, token) DO UPDATE SET updated_at = NOW()`,
      [req.user.id, fcmToken, platform || 'android']
    );
    res.json({ status: 'registered' });
  } catch (err) {
    console.error('❌ Device registration error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Notification inbox
app.get('/api/notifications', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
      [req.user.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.patch('/api/notifications/:id/read', authenticateToken, async (req, res) => {
  await pgPool.query('UPDATE notifications SET read = true WHERE id = $1 AND user_id = $2', [req.params.id, req.user.id]);
  res.json({ status: 'ok' });
});

// Notification dispatch helper — FCM → SMS fallback → in-app inbox
async function sendNotification(userId, type, data) {
  try {
    // 1. Store in-app notification
    await pgPool.query(
      'INSERT INTO notifications (user_id, type, data) VALUES ($1, $2, $3)',
      [userId, type, JSON.stringify(data)]
    );

    // 2. Try FCM push
    const tokens = await pgPool.query(
      'SELECT token FROM device_tokens WHERE user_id = $1',
      [userId]
    );

    if (tokens.rows.length > 0) {
      try {
        const admin = require('firebase-admin');
        if (admin.apps.length === 0) {
          const serviceAccount = require('./serviceAccount.json');
          admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
        }

        for (const row of tokens.rows) {
          await admin.messaging().send({
            token: row.token,
            notification: {
              title: data.title || 'ReddiHelp Alert',
              body: data.message || data.body || '',
            },
            data: {
              type,
              incidentId: String(data.incidentId || ''),
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
              priority: type === 'EVACUATION_ALERT' ? 'high' : 'normal',
              notification: {
                channelId: type === 'EVACUATION_ALERT' ? 'emergency' : 'default',
                priority: type === 'EVACUATION_ALERT' ? 'max' : 'default',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: type === 'EVACUATION_ALERT' ? 'emergency.caf' : 'default',
                  'content-available': 1,
                },
              },
            },
          }).catch(e => console.log(`⚠️ FCM send failed for token: ${e.message}`));
        }
        console.log(`📱 [FCM] Sent ${type} to user ${userId} (${tokens.rows.length} device(s))`);
        return;
      } catch (fcmErr) {
        console.log(`⚠️ FCM dispatch failed, falling back to SMS: ${fcmErr.message}`);
      }
    }

    // 3. WhatsApp fallback via Meta Cloud API
    if (process.env.WHATSAPP_TOKEN && process.env.WHATSAPP_PHONE_ID) {
      const user = await pgPool.query('SELECT phone FROM users WHERE id = $1', [userId]);
      if (user.rows.length > 0 && user.rows[0].phone) {
        const fetch = require('node-fetch');
        const phone = user.rows[0].phone.replace(/[^0-9]/g, '');
        await fetch(`https://graph.facebook.com/v21.0/${process.env.WHATSAPP_PHONE_ID}/messages`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${process.env.WHATSAPP_TOKEN}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            messaging_product: 'whatsapp',
            to: phone,
            type: 'text',
            text: { body: `[ReddiHelp] ${data.message || data.body || type}` },
          }),
        }).then(r => r.json()).catch(e => console.log(`⚠️ WhatsApp send failed: ${e.message}`));
        console.log(`📱 [WhatsApp] Sent ${type} fallback to user ${userId}`);
      }
    }
  } catch (err) {
    console.error(`❌ sendNotification error for user ${userId}:`, err.message);
  }
}

// ============================================================
// Pre-signed URL Generation for Media Upload (#8)
// ============================================================
app.post('/api/media/presign', authenticateToken, async (req, res) => {
  const { filename, contentType, incidentId } = req.body;
  if (!filename || !contentType) {
    return res.status(400).json({ error: 'filename and contentType required' });
  }

  const crypto = require('crypto');
  const mediaId = crypto.randomBytes(8).toString('hex');
  const ext = filename.split('.').pop() || 'bin';
  const key = `incidents/${incidentId || 'unlinked'}/${mediaId}.${ext}`;

  // Store media record in DB
  const result = await pgPool.query(
    `INSERT INTO media (incident_id, uploaded_by, storage_key, content_type, status)
     VALUES ($1, $2, $3, $4, 'pending') RETURNING id, storage_key`,
    [incidentId || null, req.user.id, key, contentType]
  );

  // In production: generate actual S3/GCS pre-signed URL
  // For dev/local: accept direct upload to a local /uploads endpoint
  const uploadUrl = `${req.protocol}://${req.get('host')}/api/media/upload/${result.rows[0].id}`;

  res.json({
    mediaId: result.rows[0].id,
    uploadUrl,
    storageKey: key,
    expiresIn: 3600,
  });
});

// Direct upload endpoint (local dev fallback — production uses S3 pre-signed)
const multerAvailable = (() => { try { require.resolve('multer'); return true; } catch { return false; } })();
if (multerAvailable) {
  const multer = require('multer');
  const fs = require('fs');
  const uploadDir = path.join(__dirname, 'uploads');
  if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

  const storage = multer.diskStorage({
    destination: uploadDir,
    filename: (req, file, cb) => cb(null, `${Date.now()}_${file.originalname}`),
  });
  const upload = multer({ storage, limits: { fileSize: 10 * 1024 * 1024 } }); // 10MB limit

  app.put('/api/media/upload/:mediaId', authenticateToken, upload.single('file'), async (req, res) => {
    const mediaId = parseInt(req.params.mediaId);
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    await pgPool.query(
      `UPDATE media SET status = 'uploaded', file_path = $1, uploaded_at = NOW() WHERE id = $2`,
      [req.file.path, mediaId]
    );

    res.json({ status: 'uploaded', mediaId, path: req.file.filename });
  });
} else {
  // Stub if multer not installed — accept but don't store
  app.put('/api/media/upload/:mediaId', authenticateToken, express.raw({ limit: '10mb', type: '*/*' }), async (req, res) => {
    const mediaId = parseInt(req.params.mediaId);
    await pgPool.query(
      `UPDATE media SET status = 'uploaded', uploaded_at = NOW() WHERE id = $1`,
      [mediaId]
    );
    res.json({ status: 'uploaded', mediaId });
  });
}

// Get media for an incident
app.get('/api/incidents/:id/media', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  try {
    const result = await pgPool.query(
      `SELECT * FROM media WHERE incident_id = $1 ORDER BY created_at`,
      [incidentId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Geographic Broadcast with PostGIS Polygon Query (#13 enhanced)
// ============================================================
app.post('/api/broadcasts/geographic', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const { message, polygon, expiresInHours, targetRoles } = req.body;
  if (!message) return res.status(400).json({ error: 'message required' });

  try {
    // Create broadcast record
    const expiresAt = expiresInHours
      ? new Date(Date.now() + expiresInHours * 60 * 60 * 1000).toISOString()
      : null;

    const alert = await pgPool.query(
      `INSERT INTO broadcast_alerts (message, target_roles, expires_at, created_by)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [message, targetRoles || 'all', expiresAt, req.user.id]
    );

    let affectedUsers = [];

    if (polygon && Array.isArray(polygon) && polygon.length >= 3) {
      // PostGIS polygon query: find users within the geographic area
      const polyPoints = polygon.map(p => `${p[1]} ${p[0]}`).join(',');
      const firstPoint = `${polygon[0][1]} ${polygon[0][0]}`;
      const wkt = `POLYGON((${polyPoints},${firstPoint}))`;

      const roleFilter = targetRoles && targetRoles !== 'all'
        ? `AND u.role = '${targetRoles.replace(/'/g, '')}'`
        : '';

      const users = await pgPool.query(
        `SELECT u.id, u.phone, u.role FROM users u
         WHERE u.location IS NOT NULL AND ST_Within(u.location::geometry, ST_GeomFromText($1, 4326))
         ${roleFilter}`,
        [wkt]
      );

      affectedUsers = users.rows;
    } else {
      // No polygon — broadcast to all users with matching role
      const roleFilter = targetRoles && targetRoles !== 'all'
        ? `WHERE role = '${targetRoles.replace(/'/g, '')}'`
        : '';
      const users = await pgPool.query(`SELECT id, phone, role FROM users ${roleFilter}`);
      affectedUsers = users.rows;
    }

    // Send notifications to each affected user
    for (const user of affectedUsers) {
      await sendNotification(user.id, 'EVACUATION_ALERT', {
        title: 'Emergency Broadcast Alert',
        message,
        alertId: alert.rows[0].id,
      });
    }

    // Fan out via Socket.io
    io.emit('broadcast:alert', alert.rows[0]);

    console.log(`📢 [Geographic Broadcast] Alert #${alert.rows[0].id} sent to ${affectedUsers.length} user(s)`);
    res.status(201).json({
      alert: alert.rows[0],
      affectedUserCount: affectedUsers.length,
    });
  } catch (err) {
    console.error('❌ Geographic broadcast error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Auto-Escalation for Unassigned Incidents (#11)
// ============================================================
let escalationInterval;
async function runEscalationCheck() {
  if (!pgPool) return;
  try {
    // Find incidents that are 'active' (unassigned) for more than 15 minutes
    const stale = await pgPool.query(
      `SELECT i.id, i.type, i.severity, i.submitted_by, i.reference_number
       FROM incidents i
       WHERE i.status = 'active'
         AND i.assigned_to IS NULL
         AND i.created_at < NOW() - INTERVAL '15 minutes'
         AND i.created_at > NOW() - INTERVAL '24 hours'`
    );

    for (const incident of stale.rows) {
      // Notify coordinators
      io.to('coordinators').emit('incident:escalated', {
        id: incident.id,
        type: incident.type,
        severity: incident.severity,
        message: `Incident #${incident.id} has been unassigned for over 15 minutes`,
      });

      // Bump severity if not already max
      if (incident.severity < 5) {
        await pgPool.query(
          'UPDATE incidents SET severity = LEAST(severity + 1, 5), updated_at = NOW() WHERE id = $1',
          [incident.id]
        );
      }

      // Log escalation
      await pgPool.query(
        `INSERT INTO incident_history (incident_id, from_status, to_status, changed_by)
         VALUES ($1, 'active', 'escalated', 0)
         ON CONFLICT DO NOTHING`,
        [incident.id]
      );

      console.log(`⚠️ [Escalation] Incident #${incident.id} escalated — unassigned >15min`);
    }

    if (stale.rows.length > 0) {
      console.log(`⚠️ [Escalation] ${stale.rows.length} incident(s) escalated`);
    }
  } catch (err) {
    console.error('❌ Escalation check error:', err.message);
  }
}

// Run escalation check every 2 minutes
escalationInterval = setInterval(runEscalationCheck, 2 * 60 * 1000);

// ============================================================
// Preparedness Content CMS (#16)
// ============================================================
app.get('/api/preparedness', async (req, res) => {
  try {
    const result = await pgPool.query(
      'SELECT * FROM preparedness_content WHERE published = true ORDER BY sort_order, created_at'
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/api/preparedness', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const { title, category, content, parish, sortOrder } = req.body;
  if (!title || !content) return res.status(400).json({ error: 'title and content required' });

  try {
    const result = await pgPool.query(
      `INSERT INTO preparedness_content (title, category, content, parish, sort_order, created_by, published)
       VALUES ($1, $2, $3, $4, $5, $6, true) RETURNING *`,
      [title, category || 'general', content, parish || null, sortOrder || 0, req.user.id]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('❌ Preparedness content error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// WebSocket – single middleware, MOCK_AUTH-aware
// ============================================================
io.use((socket, next) => {
  if (MOCK_AUTH) {
    socket.user = { id: 1, role: 'coordinator' };
    return next();
  }
  const token = socket.handshake.auth.token;
  jwt.verify(token, ACCESS_TOKEN_SECRET, (err, user) => {
    if (err) return next(new Error('Authentication error'));
    socket.user = user;
    next();
  });
});

io.on('connection', (socket) => {
  const user = socket.user;
  if (user.role === 'coordinator') socket.join('coordinators');
  if (user.role === 'volunteer') socket.join('volunteers');
  if (user.role === 'responder') socket.join('responders');
  console.log(`🔌 User ${user.id} (${user.role}) connected via WebSocket`);

  socket.on('subscribe:incident', (incidentId) => {
    socket.join(`incident:${incidentId}`);
    console.log(`🔔 User ${user.id} subscribed to incident:${incidentId}`);
  });

  socket.on('unsubscribe:incident', (incidentId) => {
    socket.leave(`incident:${incidentId}`);
  });

  // Chat message via Socket.io (real-time relay)
  socket.on('chat:send', async (data) => {
    const { incidentId, content, messageType } = data;
    if (!incidentId || !content) return;

    try {
      const result = await pgPool.query(
        `INSERT INTO messages (incident_id, sender_id, content, message_type)
         VALUES ($1, $2, $3, $4) RETURNING *`,
        [incidentId, user.id, content.trim(), messageType || 'text']
      );
      const message = { ...result.rows[0], sender_role: user.role };
      io.to(`incident:${incidentId}`).emit('chat:message', message);
    } catch (err) {
      socket.emit('chat:error', { error: err.message });
    }
  });

  // Typing indicator
  socket.on('chat:typing', (data) => {
    socket.to(`incident:${data.incidentId}`).emit('chat:typing', {
      userId: user.id,
      role: user.role,
    });
  });
});

// ============================================================
// Phase 1+3: Enhanced GET /api/volunteers/list with location + task counts
// ============================================================
// (replaces the original GET /api/volunteers/list defined above — keep this one)

// ============================================================
// Phase 2: GET /api/incidents/:id/history  (Incident audit trail)
// ============================================================
app.get('/api/incidents/:id/history', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  try {
    const result = await pgPool.query(
      `SELECT ih.*, u.username AS changed_by_name
       FROM incident_history ih
       LEFT JOIN users u ON u.id = ih.changed_by
       WHERE ih.incident_id = $1
       ORDER BY ih.changed_at ASC`,
      [incidentId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('❌ Incident history error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 4: Resource Management enhancements
// ============================================================
app.get('/api/resources/:id/history', authenticateToken, async (req, res) => {
  const resourceId = parseInt(req.params.id);
  try {
    const result = await pgPool.query(
      `SELECT ra.*, i.type AS incident_type, i.area_id
       FROM resource_allocations ra
       LEFT JOIN incidents i ON i.id = ra.incident_id
       WHERE ra.resource_id = $1
       ORDER BY ra.allocated_at DESC`,
      [resourceId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/api/resources/bulk-import', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const { resources } = req.body;
  if (!Array.isArray(resources) || resources.length === 0) {
    return res.status(400).json({ error: 'resources must be a non-empty array' });
  }
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    let imported = 0;
    for (const r of resources) {
      const point = r.lat && r.lon ? `POINT(${r.lon} ${r.lat})` : null;
      await client.query(
        `INSERT INTO resources (type, quantity, unit, location, name, organisation_name, alert_threshold)
         VALUES ($1, $2, $3, ${point ? 'ST_GeogFromText($4)' : 'NULL'}, $${point ? 5 : 4}, $${point ? 6 : 5}, $${point ? 7 : 6})`,
        point
          ? [r.type, r.quantity, r.unit || null, point, r.name || null, r.organisation_name || null, r.alert_threshold || 0]
          : [r.type, r.quantity, r.unit || null, r.name || null, r.organisation_name || null, r.alert_threshold || 0]
      );
      imported++;
    }
    await client.query('COMMIT');
    res.json({ imported });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Bulk import error:', err);
    res.status(500).json({ error: 'Bulk import failed' });
  } finally {
    client.release();
  }
});

app.patch('/api/resources/:id', authenticateToken, async (req, res) => {
  const resourceId = parseInt(req.params.id);
  const { quantity, notes } = req.body;
  try {
    await pgPool.query('UPDATE resources SET quantity = $1, last_updated = NOW() WHERE id = $2', [quantity, resourceId]);
    // Log restock as allocation with null incident
    await pgPool.query(
      'INSERT INTO resource_allocations (resource_id, incident_id, quantity, notes) VALUES ($1, NULL, $2, $3)',
      [resourceId, quantity, notes || 'Restocked']
    );
    const updated = await pgPool.query('SELECT * FROM resources WHERE id = $1', [resourceId]);
    res.json(updated.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 5: Broadcast enhancements
// ============================================================
app.get('/api/broadcasts/estimate-recipients', authenticateToken, async (req, res) => {
  const { polygon, center_lat, center_lon, radius_km } = req.body;
  try {
    let count = 0;
    if (polygon) {
      const coords = polygon.coordinates[0].map(c => `${c[0]} ${c[1]}`).join(',');
      const wkt = `POLYGON((${coords}))`;
      const result = await pgPool.query(
        'SELECT COUNT(*) FROM users WHERE location IS NOT NULL AND ST_Contains(ST_GeomFromText($1, 4326), location::geometry)',
        [wkt]
      );
      count = parseInt(result.rows[0].count);
    } else if (center_lat && center_lon && radius_km) {
      const result = await pgPool.query(
        'SELECT COUNT(*) FROM users WHERE location IS NOT NULL AND ST_DWithin(location, ST_GeogFromText($1), $2)',
        [`POINT(${center_lon} ${center_lat})`, radius_km * 1000]
      );
      count = parseInt(result.rows[0].count);
    } else {
      const result = await pgPool.query('SELECT COUNT(*) FROM users');
      count = parseInt(result.rows[0].count);
    }
    res.json({ count });
  } catch (err) {
    console.error('❌ Estimate recipients error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.delete('/api/broadcasts/:id', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const id = parseInt(req.params.id);
  await pgPool.query('UPDATE broadcast_alerts SET expires_at = NOW() WHERE id = $1', [id]);
  res.json({ status: 'deleted' });
});

// ============================================================
// Phase 6: Analytics endpoints
// ============================================================
app.get('/api/analytics/response-times', authenticateToken, async (req, res) => {
  const hours = parseInt(req.query.hours) || 24;
  try {
    const result = await pgPool.query(
      `SELECT
         AVG(EXTRACT(EPOCH FROM (ih.changed_at - i.created_at))) as avg_seconds,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (ih.changed_at - i.created_at))) as p50,
         PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (ih.changed_at - i.created_at))) as p90,
         PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (ih.changed_at - i.created_at))) as p95,
         COUNT(*) as sample_size
       FROM incident_history ih
       JOIN incidents i ON i.id = ih.incident_id
       WHERE ih.from_status = 'active' AND ih.to_status IN ('in-progress', 'assigned')
         AND i.created_at > NOW() - INTERVAL '1 hour' * $1`,
      [hours]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error('❌ Response times error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/analytics/timeline', authenticateToken, async (req, res) => {
  const hours = parseInt(req.query.hours) || 24;
  try {
    const result = await pgPool.query(
      `SELECT date_trunc('hour', created_at) as hour,
              COUNT(*) FILTER (WHERE status IN ('active','assigned')) as active,
              COUNT(*) FILTER (WHERE status = 'in-progress') as in_progress,
              COUNT(*) FILTER (WHERE status = 'resolved') as resolved,
              COUNT(*) as total
       FROM incidents
       WHERE created_at > NOW() - INTERVAL '1 hour' * $1
       GROUP BY hour ORDER BY hour`,
      [hours]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/analytics/volunteer-deployment', authenticateToken, async (req, res) => {
  try {
    const online = await pgPool.query(
      `SELECT COUNT(*) FROM users WHERE role IN ('volunteer','responder') AND last_location_at > NOW() - INTERVAL '30 minutes'`
    );
    const available = await pgPool.query(
      `SELECT COUNT(*) FROM users WHERE role IN ('volunteer','responder') AND availability = 'available' AND last_location_at > NOW() - INTERVAL '30 minutes'`
    );
    const onTask = await pgPool.query(
      `SELECT COUNT(*) FROM users WHERE role IN ('volunteer','responder') AND availability = 'on_task'`
    );
    const hoursToday = await pgPool.query(
      `SELECT COALESCE(SUM(hours_contributed),0) as total FROM volunteer_stats WHERE last_active_at::date = CURRENT_DATE`
    );
    res.json({
      total_online: parseInt(online.rows[0].count),
      available: parseInt(available.rows[0].count),
      on_task: parseInt(onTask.rows[0].count),
      total_hours_today: parseFloat(hoursToday.rows[0].total)
    });
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/analytics/resource-coverage', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT r.type, SUM(r.quantity) as available,
              COALESCE((SELECT SUM(ra.quantity) FROM resource_allocations ra WHERE ra.resource_id = ANY(ARRAY_AGG(r.id)) AND ra.allocated_at > NOW() - INTERVAL '24 hours'),0) as allocated
       FROM resources r GROUP BY r.type`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/analytics/health-score', authenticateToken, async (req, res) => {
  try {
    const activeResult = await pgPool.query("SELECT COUNT(*) FROM incidents WHERE status IN ('active','in-progress')");
    const unassignedResult = await pgPool.query("SELECT COUNT(*) FROM incidents WHERE status = 'active' AND assigned_to IS NULL");
    const totalActive = parseInt(activeResult.rows[0].count) || 1;
    const unassigned = parseInt(unassignedResult.rows[0].count);
    const unassigned_rate = unassigned / totalActive;

    const rtResult = await pgPool.query(
      `SELECT AVG(EXTRACT(EPOCH FROM (ih.changed_at - i.created_at)))/60 as avg_min
       FROM incident_history ih JOIN incidents i ON i.id = ih.incident_id
       WHERE ih.from_status = 'active' AND ih.to_status IN ('in-progress','assigned')
         AND i.created_at > NOW() - INTERVAL '24 hours'`
    );
    const avgMin = parseFloat(rtResult.rows[0].avg_min) || 0;
    const response_time_score = avgMin <= 15 ? 'green' : avgMin <= 30 ? 'amber' : 'red';

    const resResult = await pgPool.query(
      `SELECT AVG(CASE WHEN alert_threshold > 0 THEN quantity::float / alert_threshold ELSE 999 END) as avg_ratio FROM resources`
    );
    const ratio = parseFloat(resResult.rows[0].avg_ratio) || 999;
    const resource_score = ratio > 2 ? 'green' : ratio > 1 ? 'amber' : 'red';

    const scores = { unassigned_rate, response_time_score, resource_score };
    const redCount = [unassigned_rate > 0.6, response_time_score === 'red', resource_score === 'red'].filter(Boolean).length;
    const amberCount = [unassigned_rate > 0.3, response_time_score === 'amber', resource_score === 'amber'].filter(Boolean).length;

    const score = redCount >= 2 ? 'red' : (redCount >= 1 || amberCount >= 2) ? 'amber' : 'green';
    res.json({ score, components: scores });
  } catch (err) {
    console.error('❌ Health score error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/analytics/area-breakdown', authenticateToken, async (req, res) => {
  const hours = parseInt(req.query.hours) || 24;
  try {
    const result = await pgPool.query(
      `SELECT area_id, COUNT(*) as incident_count,
              COUNT(*) FILTER (WHERE status = 'active') as active_count
       FROM incidents WHERE created_at > NOW() - INTERVAL '1 hour' * $1
       GROUP BY area_id ORDER BY incident_count DESC`,
      [hours]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 7: Map Layers
// ============================================================
app.post('/api/map-layers', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const { name, type, geojson } = req.body;
  try {
    const result = await pgPool.query(
      'INSERT INTO map_layers (name, type, geojson, created_by) VALUES ($1, $2, $3, $4) RETURNING *',
      [name, type, JSON.stringify(geojson), req.user.id]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/map-layers', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query('SELECT * FROM map_layers WHERE active = true ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.delete('/api/map-layers/:id', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  await pgPool.query('UPDATE map_layers SET active = false WHERE id = $1', [req.params.id]);
  res.json({ status: 'deleted' });
});

app.post('/api/layer-presets', authenticateToken, async (req, res) => {
  const { name, layers } = req.body;
  try {
    const result = await pgPool.query(
      'INSERT INTO layer_presets (name, user_id, layers) VALUES ($1, $2, $3) RETURNING *',
      [name, req.user.id, JSON.stringify(layers)]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/layer-presets', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query('SELECT * FROM layer_presets WHERE user_id = $1 ORDER BY created_at DESC', [req.user.id]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 8: Incident notes
// ============================================================
app.post('/api/incidents/:id/notes', authenticateToken, async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const { note } = req.body;
  if (!note) return res.status(400).json({ error: 'note required' });
  try {
    const result = await pgPool.query(
      'INSERT INTO incident_history (incident_id, from_status, to_status, changed_by, note) VALUES ($1, NULL, NULL, $2, $3) RETURNING *',
      [incidentId, req.user.id, note]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 9: Resource Requests
// ============================================================
app.post('/api/resource-requests', authenticateToken, async (req, res) => {
  const { incident_id, resource_type, quantity, urgency, delivery_lat, delivery_lon, notes } = req.body;
  try {
    let lat = delivery_lat, lon = delivery_lon;
    if (!lat && incident_id) {
      const inc = await pgPool.query('SELECT ST_Y(location::geometry) as lat, ST_X(location::geometry) as lon FROM incidents WHERE id = $1', [incident_id]);
      if (inc.rows.length) { lat = inc.rows[0].lat; lon = inc.rows[0].lon; }
    }
    const result = await pgPool.query(
      `INSERT INTO resource_requests (incident_id, requested_by, resource_type, quantity, urgency, delivery_lat, delivery_lon, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [incident_id || null, req.user.id, resource_type, quantity, urgency || 'normal', lat, lon, notes]
    );
    io.to('coordinators').emit('resource:requested', result.rows[0]);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('❌ Resource request error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/resource-requests', authenticateToken, async (req, res) => {
  try {
    const statusFilter = req.query.status ? 'WHERE rr.status = $1' : '';
    const params = req.query.status ? [req.query.status] : [];
    const result = await pgPool.query(
      `SELECT rr.*, u.username as requested_by_name, i.type as incident_type
       FROM resource_requests rr
       LEFT JOIN users u ON rr.requested_by = u.id
       LEFT JOIN incidents i ON rr.incident_id = i.id
       ${statusFilter}
       ORDER BY CASE rr.urgency WHEN 'critical' THEN 1 WHEN 'urgent' THEN 2 ELSE 3 END, rr.created_at ASC`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.patch('/api/resource-requests/:id/fulfill', authenticateToken, async (req, res) => {
  const id = parseInt(req.params.id);
  const { resource_id, quantity } = req.body;
  try {
    await pgPool.query('UPDATE resources SET quantity = quantity - $1 WHERE id = $2 AND quantity >= $1', [quantity, resource_id]);
    await pgPool.query('INSERT INTO resource_allocations (resource_id, incident_id, quantity, notes) VALUES ($1, (SELECT incident_id FROM resource_requests WHERE id = $2), $3, $4)', [resource_id, id, quantity, 'Fulfilled request #' + id]);
    await pgPool.query('UPDATE resource_requests SET status = $1, fulfilled_by = $2, fulfilled_at = NOW() WHERE id = $3', ['fulfilled', req.user.id, id]);
    res.json({ status: 'fulfilled' });
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.patch('/api/resource-requests/:id/deny', authenticateToken, async (req, res) => {
  const id = parseInt(req.params.id);
  const { reason } = req.body;
  try {
    await pgPool.query('UPDATE resource_requests SET status = $1, notes = COALESCE(notes, $2) WHERE id = $3', ['denied', reason || 'Denied', id]);
    res.json({ status: 'denied' });
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 10: Report Generator
// ============================================================
app.get('/api/reports/generate', authenticateToken, async (req, res) => {
  const { start_date, end_date, type } = req.query;
  try {
    const dateFilter = start_date && end_date ? `AND i.created_at BETWEEN $1 AND $2` : '';
    const params = start_date && end_date ? [start_date, end_date] : [];

    const total = await pgPool.query(`SELECT COUNT(*) as total, type, severity, status FROM incidents i WHERE 1=1 ${dateFilter} GROUP BY type, severity, status`, params);
    const timeline = await pgPool.query(
      `SELECT ih.*, i.type, u.username as actor FROM incident_history ih JOIN incidents i ON i.id = ih.incident_id LEFT JOIN users u ON ih.changed_by = u.id WHERE 1=1 ${dateFilter.replace(/i\./g, 'i.')} ORDER BY ih.changed_at`,
      params
    );
    const areaBreakdown = await pgPool.query(`SELECT area_id, COUNT(*) as count FROM incidents i WHERE 1=1 ${dateFilter} GROUP BY area_id ORDER BY count DESC`, params);
    const resourceUtil = await pgPool.query(
      `SELECT r.type, SUM(ra.quantity) as allocated FROM resource_allocations ra JOIN resources r ON r.id = ra.resource_id WHERE ra.allocated_at BETWEEN COALESCE($1, '1970-01-01') AND COALESCE($2, NOW()) GROUP BY r.type`,
      [start_date || null, end_date || null]
    );
    const topVolunteers = await pgPool.query(
      `SELECT u.username, vs.tasks_completed, vs.hours_contributed FROM volunteer_stats vs JOIN users u ON u.id = vs.user_id ORDER BY vs.tasks_completed DESC LIMIT 10`
    );

    res.json({
      incidents_summary: total.rows,
      timeline: timeline.rows,
      area_breakdown: areaBreakdown.rows,
      resource_utilization: resourceUtil.rows,
      top_volunteers: topVolunteers.rows
    });
  } catch (err) {
    console.error('❌ Report generate error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/api/reports', authenticateToken, async (req, res) => {
  const { title, date_range_start, date_range_end } = req.body;
  try {
    const result = await pgPool.query(
      'INSERT INTO generated_reports (title, date_range_start, date_range_end, generated_by) VALUES ($1, $2, $3, $4) RETURNING *',
      [title, date_range_start, date_range_end, req.user.id]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/reports', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query('SELECT * FROM generated_reports ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 11: Predictive analytics
// ============================================================
app.get('/api/analytics/predictions/demand', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT area_id,
              COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '2 hours') as current_count,
              COUNT(*) FILTER (WHERE created_at BETWEEN NOW() - INTERVAL '4 hours' AND NOW() - INTERVAL '2 hours') as prev_count
       FROM incidents WHERE created_at > NOW() - INTERVAL '4 hours' GROUP BY area_id`
    );
    const predictions = result.rows.map(r => {
      const curr = parseInt(r.current_count);
      const prev = parseInt(r.prev_count) || 1;
      const growth = curr / prev;
      return {
        area_id: r.area_id,
        current_count: curr,
        predicted_count: Math.round(curr * growth * 2),
        confidence: curr >= 5 ? 'high' : curr >= 2 ? 'medium' : 'low'
      };
    });
    res.json(predictions);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/analytics/predictions/resource-shortfall', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT r.type, SUM(r.quantity) as current_qty,
              COALESCE((SELECT SUM(ra.quantity)::float / GREATEST(EXTRACT(EPOCH FROM (NOW() - MIN(ra.allocated_at))) / 3600, 1) FROM resource_allocations ra WHERE ra.resource_id = ANY(ARRAY_AGG(r.id)) AND ra.allocated_at > NOW() - INTERVAL '6 hours'), 0) as depletion_rate_per_hour
       FROM resources r GROUP BY r.type`
    );
    const predictions = result.rows.map(r => {
      const qty = parseFloat(r.current_qty);
      const rate = parseFloat(r.depletion_rate_per_hour);
      const hoursLeft = rate > 0 ? qty / rate : 999;
      return {
        type: r.type,
        current_qty: qty,
        depletion_rate_per_hour: Math.round(rate * 10) / 10,
        hours_until_empty: Math.round(hoursLeft),
        severity: hoursLeft < 4 ? 'critical' : hoursLeft < 8 ? 'warning' : 'ok'
      };
    });
    res.json(predictions);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 12: Public Status Dashboard (no auth)
// ============================================================
app.get('/api/public/status', async (req, res) => {
  try {
    const totalInc = await pgPool.query('SELECT COUNT(*) FROM incidents');
    const activeInc = await pgPool.query("SELECT COUNT(*) FROM incidents WHERE status IN ('active','in-progress')");
    const volunteers = await pgPool.query("SELECT COUNT(*) FROM users WHERE role IN ('volunteer','responder') AND last_location_at > NOW() - INTERVAL '30 minutes'");
    const resources = await pgPool.query("SELECT COALESCE(SUM(quantity),0) as total FROM resources WHERE status = 'available'");

    const activeCount = parseInt(activeInc.rows[0].count);
    const overall_status = activeCount > 10 ? 'Active' : activeCount > 0 ? 'Contained' : 'Recovery';

    res.json({
      overall_status,
      total_incidents: parseInt(totalInc.rows[0].count),
      active_incidents: activeCount,
      volunteers_deployed: parseInt(volunteers.rows[0].count),
      resources_available: parseInt(resources.rows[0].total),
      last_updated: new Date().toISOString()
    });
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Phase 14: AI Dispatch Recommendation Engine
// ============================================================
app.get('/api/incidents/:id/match-enhanced', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  const incidentId = parseInt(req.params.id);
  const maxDistance = parseInt(req.query.maxDistance) || 20000;

  try {
    const incident = await pgPool.query(
      'SELECT *, ST_X(location::geometry) as lon, ST_Y(location::geometry) as lat FROM incidents WHERE id = $1',
      [incidentId]
    );
    if (incident.rows.length === 0) return res.status(404).json({ error: 'Incident not found' });

    const inc = incident.rows[0];
    const skillMap = {
      medical: ['First Aid/CPR', 'Medical Professional', 'Basic Life Support'],
      fire: ['Firefighting', 'Hazmat', 'Search & Rescue'],
      flood: ['Swift Water Rescue', 'Flood Response'],
      trapped: ['Search & Rescue', 'Heavy Equipment'],
      supplies: ['Logistics', 'Transport'],
      shelter: ['Logistics', 'Mental Health'],
    };
    const relevantSkills = skillMap[inc.type] || [];

    const candidates = await pgPool.query(
      `SELECT u.id, u.username, u.phone, u.role, u.skills, u.vehicle, u.availability,
              u.last_lat, u.last_lon, u.active_location_lat, u.active_location_lon,
              ST_Distance(u.location, ST_GeogFromText($1)) as distance
       FROM users u
       WHERE u.role IN ('volunteer', 'responder')
         AND u.availability = 'available'
         AND u.last_lat IS NOT NULL
         AND ST_DWithin(u.location, ST_GeogFromText($1), $2)
       ORDER BY distance ASC LIMIT 20`,
      [`POINT(${inc.lon} ${inc.lat})`, maxDistance]
    );

    // Get experience counts
    const expCounts = await pgPool.query(
      `SELECT assigned_to, COUNT(*) as completed FROM incidents WHERE status = 'resolved' AND assigned_to = ANY($1) GROUP BY assigned_to`,
      [candidates.rows.map(c => c.id)]
    );
    const expMap = {};
    expCounts.rows.forEach(r => { expMap[r.assigned_to] = parseInt(r.completed); });

    const scored = candidates.rows.map(c => {
      const userSkills = c.skills || [];
      const matchedSkills = relevantSkills.filter(s => userSkills.some(us => us.toLowerCase().includes(s.toLowerCase())));
      const skillScore = relevantSkills.length > 0 ? matchedSkills.length / relevantSkills.length : 0;
      const distScore = 1 - Math.min(c.distance, maxDistance) / maxDistance;
      const availScore = c.availability === 'available' ? 1 : 0;
      const exp = expMap[c.id] || 0;
      const expScore = Math.min(exp / 10, 1);

      // Active-location boost: +15% if within 10km of preferred region
      let activeLocBoost = 0;
      if (c.active_location_lat && c.active_location_lon) {
        const dLat = (c.active_location_lat - inc.lat) * 111320;
        const dLon = (c.active_location_lon - inc.lon) * 111320 * Math.cos(inc.lat * Math.PI / 180);
        const activeLocDist = Math.sqrt(dLat * dLat + dLon * dLon);
        if (activeLocDist <= 10000) activeLocBoost = 0.15;
      }

      const confidence = Math.min(100, Math.round((distScore * 0.4 + skillScore * 0.3 + availScore * 0.2 + expScore * 0.1 + activeLocBoost) * 100));

      const reasoning = [];
      reasoning.push(`${(c.distance / 1000).toFixed(1)}km away`);
      if (matchedSkills.length > 0) reasoning.push(`Skills: ${matchedSkills.join(', ')}`);
      if (c.availability === 'available') reasoning.push('Currently available');
      if (exp > 0) reasoning.push(`Completed ${exp} similar tasks`);
      if (c.vehicle) reasoning.push(`Has ${c.vehicle}`);

      return {
        userId: c.id,
        username: c.username,
        phone: c.phone,
        role: c.role,
        skills: c.skills,
        vehicle: c.vehicle,
        distance: Math.round(c.distance),
        confidence_score: confidence,
        reasoning,
        lat: c.last_lat,
        lon: c.last_lon
      };
    });

    scored.sort((a, b) => b.confidence_score - a.confidence_score);
    res.json({ incidentId, incidentType: inc.type, candidates: scored });
  } catch (err) {
    console.error('❌ Enhanced matching error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/api/auto-dispatch/run', authenticateToken, authorize('coordinator', 'admin'), async (req, res) => {
  try {
    const unassigned = await pgPool.query(
      `SELECT id, type, ST_X(location::geometry) as lon, ST_Y(location::geometry) as lat
       FROM incidents WHERE status = 'active' AND assigned_to IS NULL`
    );

    const autoAssigned = [];
    const needsApproval = [];
    const manualReview = [];

    for (const inc of unassigned.rows) {
      const candidates = await pgPool.query(
        `SELECT u.id, u.username, u.skills, u.availability,
                ST_Distance(u.location, ST_GeogFromText($1)) as distance
         FROM users u
         WHERE u.role IN ('volunteer','responder') AND u.availability = 'available'
           AND u.last_lat IS NOT NULL AND ST_DWithin(u.location, ST_GeogFromText($1), 20000)
         ORDER BY distance ASC LIMIT 5`,
        [`POINT(${inc.lon} ${inc.lat})`]
      );

      if (candidates.rows.length === 0) {
        manualReview.push({ incidentId: inc.id, reason: 'No candidates found' });
        continue;
      }

      const best = candidates.rows[0];
      const distScore = 1 - Math.min(best.distance, 20000) / 20000;
      const confidence = Math.round(distScore * 100);

      const entry = { incidentId: inc.id, volunteerId: best.id, volunteerName: best.username, confidence, distance: Math.round(best.distance) };

      if (confidence > 80) {
        // Auto-assign
        await pgPool.query('UPDATE incidents SET assigned_to = $1, status = $2, updated_at = NOW() WHERE id = $3', [best.id, 'in-progress', inc.id]);
        await pgPool.query("UPDATE users SET availability = 'on_task' WHERE id = $1", [best.id]);
        await pgPool.query('INSERT INTO incident_history (incident_id, from_status, to_status, changed_by) VALUES ($1, $2, $3, $4)', [inc.id, 'active', 'in-progress', req.user.id]);
        await pgPool.query('INSERT INTO dispatch_decisions (incident_id, volunteer_id, confidence, decision) VALUES ($1, $2, $3, $4)', [inc.id, best.id, confidence, 'auto_assigned']);
        io.to('coordinators').emit('incident:updated', { id: inc.id, status: 'in-progress', assignedTo: best.id });
        autoAssigned.push(entry);
      } else if (confidence >= 50) {
        await pgPool.query('INSERT INTO dispatch_decisions (incident_id, volunteer_id, confidence, decision) VALUES ($1, $2, $3, $4)', [inc.id, best.id, confidence, 'needs_approval']);
        needsApproval.push(entry);
      } else {
        manualReview.push({ incidentId: inc.id, reason: `Low confidence (${confidence}%)` });
      }
    }

    res.json({ auto_assigned: autoAssigned, needs_approval: needsApproval, manual_review: manualReview });
  } catch (err) {
    console.error('❌ Auto dispatch error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/dispatch-decisions', authenticateToken, async (req, res) => {
  try {
    const result = await pgPool.query(
      `SELECT dd.*, i.type as incident_type, u.username as volunteer_name
       FROM dispatch_decisions dd
       LEFT JOIN incidents i ON i.id = dd.incident_id
       LEFT JOIN users u ON u.id = dd.volunteer_id
       ORDER BY dd.decided_at DESC LIMIT 50`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// ============================================================
// Start server
// ============================================================
function getNetworkUrls(port) {
  const interfaces = os.networkInterfaces();
  const urls = [];
  for (const name in interfaces) {
    for (const iface of interfaces[name]) {
      if (!iface.internal && iface.family === 'IPv4') {
        urls.push(`http://${iface.address}:${port}`);
      }
    }
  }
  return urls;
}

const PORT = process.env.PORT || 3000;
const SHUTDOWN_TIMEOUT_MS = parseInt(process.env.SHUTDOWN_TIMEOUT_MS || '10000', 10);
let isShuttingDown = false;

function gracefulShutdown(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;

  console.log(`\n🛑 ${signal} received. Starting graceful shutdown...`);

  if (escalationInterval) {
    clearInterval(escalationInterval);
    escalationInterval = undefined;
    console.log('⏹️  Escalation interval stopped');
  }

  const forceExitTimer = setTimeout(() => {
    console.error('❌ Graceful shutdown timed out. Forcing exit.');
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  forceExitTimer.unref();

  server.close(async () => {
    try {
      if (pgPool) {
        await pgPool.end();
        console.log('✅ PostgreSQL pool closed');
      }

      clearTimeout(forceExitTimer);
      console.log('✅ Graceful shutdown complete');
      process.exit(0);
    } catch (err) {
      clearTimeout(forceExitTimer);
      console.error('❌ Error during shutdown:', err.message);
      process.exit(1);
    }
  });
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

server.listen(PORT, '0.0.0.0', () => {
  console.log('\n' + '='.repeat(50));
  console.log('🚀 SERVER STARTED SUCCESSFULLY');
  console.log('='.repeat(50));
  console.log(`\n📱 Local access:`);
  console.log(`   http://localhost:${PORT}`);
  const networkUrls = getNetworkUrls(PORT);
  if (networkUrls.length > 0) {
    console.log(`\n🌐 Network access:`);
    networkUrls.forEach(url => console.log(`   ${url}`));
  }
  console.log(`\n📋 Pages:`);
  console.log(`   🗺️  Map:       http://localhost:${PORT}/`);
  console.log(`   📊 Dashboard: http://localhost:${PORT}/incidents`);
  console.log(`\n🔧 Mode: MOCK_AUTH=${MOCK_AUTH} | TESTING_MODE=${process.env.TESTING_MODE !== 'false'}`);
  console.log('='.repeat(50) + '\n');
});
