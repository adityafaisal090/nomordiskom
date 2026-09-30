import fs from 'fs';
import path from 'path';
import db from '../config/database';

/**
 * Run migration SQL files from the migrations/ directory for SQLite.
 */
export function runMigrations(): void {
  const migrationsDir = path.join(__dirname, '..', '..', 'migrations');
  const files = fs.readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  console.log(`📦 Found ${files.length} migration file(s)`);

  for (const file of files) {
    const filePath = path.join(migrationsDir, file);
    const sql = fs.readFileSync(filePath, 'utf-8');

    console.log(`⏳ Running migration: ${file}`);
    db.exec(sql);
    console.log(`✅ Migration complete: ${file}`);
  }

  console.log('🎉 All migrations done!');
}

if (require.main === module) {
  try {
    runMigrations();
    process.exit(0);
  } catch (err: any) {
    console.error('❌ Migration failed:', err?.message || err);
    process.exit(1);
  }
}
