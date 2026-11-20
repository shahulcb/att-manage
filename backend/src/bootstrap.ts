import bcrypt from 'bcryptjs';
import { prisma, getSettings } from './db';

export async function ensureOwner() {
  const username = process.env.OWNER_USERNAME || 'owner';
  const exists = await prisma.owner.findFirst(); // single owner
  if (!exists) await prisma.owner.create({ data: { username, passwordHash: await bcrypt.hash(process.env.OWNER_PASSWORD || 'owner123', 10) } });
  await getSettings();
}
