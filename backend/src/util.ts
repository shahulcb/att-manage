import { Request, Response, NextFunction } from 'express';

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
export const wrap = (fn: (req: Request, res: Response) => Promise<unknown>) =>
  (req: Request, res: Response, next: NextFunction) => fn(req, res).catch(next);

export function errorHandler(err: any, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof HttpError) return res.status(err.status).json({ code: err.code, message: err.message });
  if (err?.name === 'ZodError') return res.status(400).json({ code: 'VALIDATION', message: err.issues?.map((i: any) => `${i.path.join('.')}: ${i.message}`).join('; ') });
  console.error(err);
  res.status(500).json({ code: 'SERVER_ERROR', message: 'Something went wrong' });
}

// ---- time helpers (organisation timezone) ----
export function localParts(d: Date, tz: string) {
  const f = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', weekday: 'short',
  });
  const p: Record<string, string> = {};
  for (const x of f.formatToParts(d)) p[x.type] = x.value;
  const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday);
  return { date: `${p.year}-${p.month}-${p.day}`, minutes: Number(p.hour) * 60 + Number(p.minute), dow };
}
export const hhmm = (s: string) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };

export function haversineM(lat1: number, lng1: number, lat2: number, lng2: number) {
  const R = 6371000, r = (x: number) => (x * Math.PI) / 180;
  const a = Math.sin(r(lat2 - lat1) / 2) ** 2 + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export function cosine(a: number[], b: number[]) {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}
