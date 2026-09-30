import Database, { Database as DatabaseType } from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import dotenv from 'dotenv';

dotenv.config();
process.env.TZ = process.env.TZ || 'Asia/Jakarta';

// Ensure data directory exists
const dataDir = path.join(__dirname, '..', '..', 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, 'siagenda.sqlite');

// Initialize SQLite database
const db: DatabaseType = new Database(dbPath);

// Enable Foreign Keys & Write-Ahead Logging for concurrency
db.pragma('foreign_keys = ON');
db.pragma('journal_mode = WAL');

console.log(`✅ Connected to SQLite database at: ${dbPath}`);
console.log('📍 Timezone: Asia/Jakarta (WIB)');

export default db;
