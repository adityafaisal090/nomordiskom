import { Request, Response, NextFunction } from 'express';

/**
 * Middleware factory: restrict access to specific role(s).
 * Must be used AFTER authenticate middleware (req.user must exist).
 * 
 * Usage:
 *   router.get('/admin-only', authenticate, authorize('admin'), handler);
 *   router.get('/both', authenticate, authorize('admin', 'operator'), handler);
 */
export function authorize(...allowedRoles: string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ message: 'Akses ditolak. Silakan login terlebih dahulu.' });
      return;
    }

    if (!allowedRoles.includes(req.user.role)) {
      res.status(403).json({ message: 'Anda tidak memiliki akses untuk fitur ini.' });
      return;
    }

    next();
  };
}
