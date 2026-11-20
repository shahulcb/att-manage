import bcrypt from 'bcryptjs';
import { prisma, getSettings } from './db';

const isProd = () => process.env.NODE_ENV === 'production';
const strong = (p?: string): p is string => !!p && p.length >= 10 && p !== 'owner123';

/** True while the local "break-glass" owner still has the well-known default password in production: that login is refused. */
export const state = { localOwnerLocked: false };

/**
 * The local "break-glass" owner (works when the ERP is down). The server ALWAYS starts; it never seeds or migrates anything here.
 * - OWNER_PASSWORD (when set and strong) creates the owner or updates its stored password.
 * - In production, if the stored owner password is still the default "owner123" (and no strong OWNER_PASSWORD is given),
 *   the local owner login is switched off and a warning is printed, instead of leaving the app open or refusing to start.
 */
export async function ensureOwner() {
  const username = process.env.OWNER_USERNAME || 'owner';
  const pw = process.env.OWNER_PASSWORD;
  if (pw && !strong(pw) && isProd()) console.warn('WARNING: OWNER_PASSWORD is too weak (need 10+ characters, not "owner123"); ignoring it.');

  let owner = await prisma.owner.findFirst(); // single owner
  if (!owner) {
    if (strong(pw) || !isProd()) {
      owner = await prisma.owner.create({ data: { username, passwordHash: await bcrypt.hash(pw || 'owner123', 10) } });
    } else {
      console.warn('WARNING: no local owner exists and OWNER_PASSWORD is not set. Sign-in is only possible through the ERP.');
    }
  } else if (strong(pw) && !(await bcrypt.compare(pw, owner.passwordHash))) {
    owner = await prisma.owner.update({ where: { id: owner.id }, data: { passwordHash: await bcrypt.hash(pw, 10) } });
    console.log('Owner password updated from OWNER_PASSWORD');
  }

  state.localOwnerLocked = isProd() && !!owner && (await bcrypt.compare('owner123', owner.passwordHash));
  if (state.localOwnerLocked) console.warn('WARNING: the local owner still has the default password, so local owner login is DISABLED. Set OWNER_PASSWORD (10+ characters) in the environment to enable it.');
  await getSettings();
}
