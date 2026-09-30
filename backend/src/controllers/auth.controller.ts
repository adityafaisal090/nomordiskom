import { Request, Response } from 'express';
import { loginUser, getUserById } from '../services/auth.service';

/**
 * POST /api/auth/login
 * Body: { username, password }
 * Returns: { token, user: { id, username, nama, role } }
 */
export async function login(req: Request, res: Response): Promise<void> {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      res.status(400).json({ message: 'Username dan password wajib diisi.' });
      return;
    }

    const result = await loginUser(username, password);
    res.json(result);
  } catch (error: any) {
    res.status(401).json({ message: error.message || 'Username atau password salah' });
  }
}

/**
 * GET /api/auth/me
 * Protected: requires authenticate middleware
 * Returns: { id, username, nama, role }
 */
export async function me(req: Request, res: Response): Promise<void> {
  try {
    if (!req.user) {
      res.status(401).json({ message: 'Akses ditolak.' });
      return;
    }

    // Re-fetch from DB to check is_active (not just relying on token payload)
    const user = await getUserById(req.user.id);

    if (!user) {
      res.status(401).json({ message: 'Akun tidak ditemukan atau sudah dinonaktifkan.' });
      return;
    }

    res.json(user);
  } catch (error: any) {
    res.status(500).json({ message: 'Terjadi kesalahan server.' });
  }
}

/**
 * POST /api/auth/logout
 * Formal endpoint — JWT is stateless, actual cleanup on client side.
 * Returns: { message: "Logout berhasil" }
 */
export async function logout(req: Request, res: Response): Promise<void> {
  res.json({ message: 'Logout berhasil' });
}
