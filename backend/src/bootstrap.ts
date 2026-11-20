import bcrypt from 'bcryptjs';
import { prisma, getSettings } from './db';

const prod = process.env.NODE_ENV === 'production';

/**
 * The local "break-glass" owner (works when the ERP is down).
 * OWNER_PASSWORD in the environment is the source of truth: setting it creates the owner or updates the stored password.
 * In production a missing/default password is refused, so the app can never go live with owner/owner123.
 */
export async function ensureOwner() {
  const username = process.env.OWNER_USERNAME || 'owner';
  const pw = process.env.OWNER_PASSWORD;
  if (prod && (!pw || pw.length < 10 || pw === 'owner123')) throw new Error('OWNER_PASSWORD must be set to a strong password (10+ characters) in production');

  const exists = await prisma.owner.findFirst(); // single owner
  if (!exists) {
    await prisma.owner.create({ data: { username, passwordHash: await bcrypt.hash(pw || 'owner123', 10) } });
  } else if (pw && !(await bcrypt.compare(pw, exists.passwordHash))) {
    await prisma.owner.update({ where: { id: exists.id }, data: { passwordHash: await bcrypt.hash(pw, 10) } });
    console.log('Owner password updated from OWNER_PASSWORD');
  }
  await getSettings();
}
