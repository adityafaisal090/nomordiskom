import { Router } from 'express';
import { login, me, logout } from '../controllers/auth.controller';
import { authenticate } from '../middleware/authenticate';

const router = Router();

// Public
router.post('/login', login);

// Protected
router.get('/me', authenticate, me);
router.post('/logout', authenticate, logout);

export default router;
