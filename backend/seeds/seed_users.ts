import bcrypt from 'bcrypt';
import dotenv from 'dotenv';
import path from 'path';

// Load .env from backend root
dotenv.config({ path: path.join(__dirname, '..', '.env') });
process.env.TZ = process.env.TZ || 'Asia/Jakarta';

import db from '../src/config/database';
import { runMigrations } from '../src/scripts/migrate';

const SALT_ROUNDS = 10;

interface SeedUser {
  username: string;
  password: string;  // Plain text — will be hashed before insert, NEVER stored as-is
  nama: string;
  role: 'admin' | 'operator';
}

const users: SeedUser[] = [
  {
    username: 'admin',
    password: 'admin123',
    nama: 'Administrator',
    role: 'admin',
  },
  {
    username: 'operator',
    password: 'operator123',
    nama: 'Operator Satu',
    role: 'operator',
  },
];

export async function seedUsers(): Promise<void> {
  console.log('🌱 Seeding users...\n');

  // Ensure tables exist before seeding
  runMigrations();

  const insertStmt = db.prepare(`
    INSERT INTO users (username, password_hash, nama, role, is_active)
    VALUES (?, ?, ?, ?, 1)
    ON CONFLICT(username) DO UPDATE SET
      password_hash = excluded.password_hash,
      nama = excluded.nama,
      role = excluded.role
  `);

  for (const user of users) {
    // Trim password to prevent whitespace hashing issues
    const trimmedPassword = user.password.trim();
    const passwordHash = await bcrypt.hash(trimmedPassword, SALT_ROUNDS);

    insertStmt.run(user.username, passwordHash, user.nama, user.role);
    console.log(`  ✅ ${user.role.toUpperCase()} — username: "${user.username}"`);
  }

  console.log('\n🎉 Seeding complete!');
  console.log('⚠️  Dev passwords: admin123 / operator123\n');
}

if (require.main === module) {
  seedUsers()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('❌ Seeding failed:', err?.message || err);
      process.exit(1);
    });
}
