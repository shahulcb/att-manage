import bcrypt from 'bcryptjs';
import { prisma, getSettings } from './db';

const isProd = () => process.env.NODE_ENV === 'production';
const strong = (p?: string): p is string => !!p && p.length >= 10 && p !== 'owner123';

/** True while the owner still has the well-known default password in production: owner sign-in is refused. */
export const state = { localOwnerLocked: false };

/**
 * Makes sure the OWNER account exists in the User collection. The server ALWAYS starts; nothing is seeded or migrated here.
 * - OWNER_PASSWORD (when set and strong) creates the owner or updates the stored password.
 * - An owner from the old Owner collection is copied into User once.
 * - In production, an owner that still has the default password "owner123" is locked out until a strong OWNER_PASSWORD is set.
 */
export async function ensureOwner() {
  const username = (process.env.OWNER_USERNAME || 'owner').trim().toLowerCase();
  const pw = process.env.OWNER_PASSWORD;
  if (pw && !strong(pw) && isProd()) console.warn('WARNING: OWNER_PASSWORD is too weak (need 10+ characters, not "owner123"); ignoring it.');

  let owner = await prisma.user.findFirst({ where: { role: 'OWNER' } });
  if (!owner) {
    const legacy = await prisma.owner.findFirst();
    if (legacy) {
      owner = await prisma.user.create({ data: { username: legacy.username.toLowerCase(), passwordHash: legacy.passwordHash, role: 'OWNER' } });
      console.log('Copied the existing owner into the User collection');
    } else if (strong(pw) || !isProd()) {
      owner = await prisma.user.create({ data: { username, passwordHash: await bcrypt.hash(pw || 'owner123', 10), role: 'OWNER' } });
    } else {
      console.warn('WARNING: no owner account exists and OWNER_PASSWORD is not set, so nobody can sign in as the owner.');
    }
  }
  if (owner && strong(pw) && !(await bcrypt.compare(pw, owner.passwordHash))) {
    owner = await prisma.user.update({ where: { id: owner.id }, data: { passwordHash: await bcrypt.hash(pw, 10) } });
    console.log('Owner password updated from OWNER_PASSWORD');
  }
  state.localOwnerLocked = isProd() && !!owner && (await bcrypt.compare('owner123', owner.passwordHash));
  if (state.localOwnerLocked) console.warn('WARNING: the owner still has the default password, so owner sign-in is DISABLED. Set OWNER_PASSWORD (10+ characters) in the environment.');

  // the old built-in demo ERP no longer exists: drop its address so nothing tries to call it
  const s = await getSettings();
  if (s.erpLoginUrl.includes('/mock-erp/')) await prisma.settings.update({ where: { id: 'main' }, data: { erpLoginUrl: '' } });
}
