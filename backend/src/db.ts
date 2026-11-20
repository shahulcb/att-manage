import { PrismaClient } from '@prisma/client';
export const prisma = new PrismaClient();

export async function getSettings() {
  return prisma.settings.upsert({ where: { id: 'main' }, update: {}, create: { id: 'main' } });
}
export async function audit(action: string, detail: unknown) {
  await prisma.auditLog.create({ data: { action, detail: JSON.stringify(detail) } });
}
