import { getSettings } from './db';
import { HttpError } from './util';

export const get = (o: any, path: string) => (path ? path.split('.').reduce((a, k) => (a == null ? a : a[k]), o) : o);

export type ErpUser = { externalId: string; name: string; email: string; department: string; active: boolean; isOwner: boolean };

/**
 * Verifies a username/password against the main ERP's login API and returns the user profile.
 * The ERP stays the single source of truth for passwords; we never store them.
 */
export async function erpLogin(username: string, password: string): Promise<ErpUser> {
  const s = await getSettings();
  if (!s.erpLoginUrl) throw new HttpError(503, 'ERP_NOT_CONFIGURED', 'ERP login is not configured yet');
  let extra: Record<string, string> = {};
  try { extra = JSON.parse(s.erpLoginHeaders || '{}'); } catch { /* ignore bad json */ }

  let res: Response;
  try {
    res = await fetch(s.erpLoginUrl, {
      method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json', ...extra },
      body: JSON.stringify({ [s.erpUserField]: username, [s.erpPassField]: password }), signal: AbortSignal.timeout(15000),
    });
  } catch { throw new HttpError(503, 'ERP_UNAVAILABLE', 'The company system is not reachable. Try again shortly.'); }

  if ([400, 401, 403, 404, 422].includes(res.status)) throw new HttpError(401, 'BAD_CREDENTIALS', 'Wrong username or password');
  if (!res.ok) throw new HttpError(503, 'ERP_UNAVAILABLE', `The company system returned an error (${res.status}).`);

  let body: any;
  try { body = await res.json(); } catch { throw new HttpError(502, 'ERP_BAD_RESPONSE', 'Company system sent an unreadable response'); }
  const u = get(body, s.erpUserPath);
  const m = JSON.parse(s.erpLoginMap) as Record<string, string>;
  const externalId = String(get(u, m.externalId) ?? '').trim();
  if (!u || !externalId) throw new HttpError(502, 'ERP_BAD_RESPONSE', 'Company system response has no user id (check the login field mapping)');
  const role = String(get(u, m.role) ?? '').toLowerCase();
  const owners = s.erpOwnerRoles.split(',').map(x => x.trim().toLowerCase()).filter(Boolean);
  return {
    externalId, name: String(get(u, m.name) ?? externalId).trim(), email: String(get(u, m.email) ?? ''),
    department: String(get(u, m.department) ?? ''),
    active: m.active ? ![false, 0, 'false', '0', 'inactive'].includes(get(u, m.active)) : true,
    isOwner: !!role && owners.includes(role),
  };
}

// simple in-memory brute-force guard: 8 failures / 15 min per ip+username
const fails = new Map<string, { n: number; t: number }>();
export function checkLoginAllowed(key: string) {
  const f = fails.get(key);
  if (f && Date.now() - f.t < 15 * 60_000 && f.n >= 8) throw new HttpError(429, 'TOO_MANY_ATTEMPTS', 'Too many failed attempts. Try again in 15 minutes.');
}
export function recordLoginFail(key: string) {
  const f = fails.get(key);
  fails.set(key, !f || Date.now() - f.t >= 15 * 60_000 ? { n: 1, t: Date.now() } : { n: f.n + 1, t: f.t });
}
export const clearLoginFails = (key: string) => fails.delete(key);
