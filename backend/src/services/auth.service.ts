import bcrypt from 'bcrypt';
import jwt, { SignOptions } from 'jsonwebtoken';
import db from '../config/database';

const JWT_SECRET: jwt.Secret = process.env.JWT_SECRET || 'fallback_secret_do_not_use_in_prod';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

export interface UserPayload {
  id: number;
  username: string;
  nama: string;
  role: string;
}

export interface LoginResult {
  token: string;
  user: UserPayload;
}

/**
 * Authenticate user by username and password.
 * Returns JWT token and user data on success.
 * Throws generic error on failure (don't reveal which field is wrong).
 */
export async function loginUser(username: string, password: string): Promise<LoginResult> {
  const trimmedUsername = username.trim();
  const trimmedPassword = password.trim();

  const stmt = db.prepare(
    'SELECT id, username, password_hash, nama, role, is_active FROM users WHERE username = ?'
  );
  const user = stmt.get(trimmedUsername) as any;

  if (!user) {
    throw new Error('Username atau password salah');
  }

  // is_active can be 1 or true
  if (!user.is_active) {
    throw new Error('Username atau password salah');
  }

  const isPasswordValid = await bcrypt.compare(trimmedPassword, user.password_hash);

  if (!isPasswordValid) {
    throw new Error('Username atau password salah');
  }

  const payload: UserPayload = {
    id: Number(user.id),
    username: user.username,
    nama: user.nama,
    role: user.role,
  };

  const signOptions: SignOptions = { expiresIn: JWT_EXPIRES_IN as any };
  const token = jwt.sign(payload, JWT_SECRET, signOptions);

  return { token, user: payload };
}

/**
 * Verify JWT token and return decoded payload.
 */
export function verifyToken(token: string): UserPayload {
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as UserPayload;
    return decoded;
  } catch {
    throw new Error('Token tidak valid atau sudah kedaluwarsa');
  }
}

/**
 * Get user data by ID (for /me endpoint — checks is_active from DB, not just token).
 */
export async function getUserById(id: number): Promise<UserPayload | null> {
  const stmt = db.prepare(
    'SELECT id, username, nama, role FROM users WHERE id = ? AND is_active = 1'
  );
  const user = stmt.get(id) as any;

  if (!user) {
    return null;
  }

  return {
    id: Number(user.id),
    username: user.username,
    nama: user.nama,
    role: user.role,
  };
}
