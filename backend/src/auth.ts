import jwt from 'jsonwebtoken';
import { Request, Response, NextFunction } from 'express';
import { HttpError } from './util';

// Production must never fall back to a known signing key: anyone could forge an owner token with it.
if (process.env.NODE_ENV === 'production' && (process.env.JWT_SECRET ?? '').length < 32)
  throw new Error('JWT_SECRET must be set to a random string of at least 32 characters in production');
const SECRET = process.env.JWT_SECRET || 'dev-secret';
export type Claims = { role: 'owner' | 'employee'; id: string };

export const sign = (c: Claims) => jwt.sign(c, SECRET, { expiresIn: '7d' });

export function requireRole(role: 'owner' | 'employee') {
  return (req: Request, _res: Response, next: NextFunction) => {
    const h = req.headers.authorization || '';
    try {
      const c = jwt.verify(h.replace(/^Bearer /, ''), SECRET) as Claims;
      if (c.role !== role) throw new Error();
      (req as any).user = c;
      next();
    } catch { next(new HttpError(401, 'UNAUTHORIZED', 'Please log in again')); }
  };
}
export const uid = (req: Request) => ((req as any).user as Claims).id;
