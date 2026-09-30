import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

// Load environment variables first
dotenv.config();
process.env.TZ = process.env.TZ || 'Asia/Jakarta';

import authRoutes from './routes/auth.routes';
import { seedUsers } from '../seeds/seed_users';

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/auth', authRoutes);

// 404 handler
app.use((_req, res) => {
  res.status(404).json({ message: 'Endpoint tidak ditemukan.' });
});

// Global error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ message: 'Terjadi kesalahan server.' });
});

// ── AUTO STARTUP: migrate + seed + start server ──
// No need to run `npm run migrate` or `npm run seed` manually!
async function startServer() {
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║        SIAGENDA Backend — Auto Startup       ║');
  console.log('╚══════════════════════════════════════════════╝\n');

  try {
    // Step 1: Auto-migrate (creates tables if they don't exist)
    console.log('📦 [1/3] Auto-migrating database...');
    // seedUsers internally calls runMigrations(), so tables are always created first

    // Step 2: Auto-seed (creates default admin & operator accounts if missing)
    console.log('🌱 [2/3] Auto-seeding default users...');
    await seedUsers();
    console.log('✅ Database ready!\n');

    // Step 3: Start Express server
    console.log('🚀 [3/3] Starting server...');
    app.listen(PORT, () => {
      console.log(`\n✅ SIAGENDA Backend running on http://localhost:${PORT}`);
      console.log(`📍 Timezone: ${process.env.TZ || 'system default'}`);
      console.log('💡 Tip: Kamu tidak perlu run migrate/seed manual lagi!\n');
    });
  } catch (err) {
    console.error('❌ Failed to start server:', err);
    process.exit(1);
  }
}

startServer();

export default app;
