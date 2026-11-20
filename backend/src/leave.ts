import { prisma } from './db';
import { eachDate } from './punch';

export const LEAVE_TYPES = ['CASUAL', 'SICK', 'OTHER'] as const;
type S = { workDays: string; holidays: string; leaveQuotaEnabled: boolean; leaveQuotaCasual: number; leaveQuotaSick: number; leaveQuotaOther: number; leaveYearStartMonth: number };

/** The leave year a date belongs to, named by the calendar year it starts in. */
export const leaveYearOf = (date: string, startMonth: number) => {
  const [y, m] = date.split('-').map(Number);
  return m >= startMonth ? y : y - 1;
};
export const leaveYearLabel = (sy: number, startMonth: number) =>
  startMonth === 1 ? `${sy}` : `${sy}-${String((sy + 1) % 100).padStart(2, '0')}`;

const isWorking = (s: S, date: string) =>
  s.workDays.split(',').map(Number).includes(new Date(date + 'T00:00:00Z').getUTCDay()) && !s.holidays.split(',').map(x => x.trim()).includes(date);

/** Working days a leave consumes, bucketed by leave year (holidays and non-working days are free). */
export function countLeaveDays(s: S, from: string, to: string, half: boolean) {
  const buckets: Record<string, number> = {};
  let total = 0;
  for (const d of eachDate(from, to)) {
    if (!isWorking(s, d)) continue;
    const y = String(leaveYearOf(d, s.leaveYearStartMonth));
    const v = half ? 0.5 : 1;
    buckets[y] = (buckets[y] ?? 0) + v; total += v;
  }
  return { total, buckets };
}

export const quotaFor = (s: S, type: string): number | null =>
  !s.leaveQuotaEnabled ? null : type === 'CASUAL' ? s.leaveQuotaCasual : type === 'SICK' ? s.leaveQuotaSick : s.leaveQuotaOther;

/** quota / used (approved) / pending (reserved) / available for one employee, type and leave year */
export async function balanceFor(s: S, employeeId: string, type: string, sy: number, excludeId?: string) {
  const rows = await prisma.leaveRequest.findMany({ where: { employeeId, type, status: { in: ['PENDING', 'APPROVED'] } } });
  let used = 0, pending = 0;
  for (const r of rows) {
    if (r.id === excludeId) continue;
    const d = (JSON.parse(r.daysJson || '{}')[String(sy)] as number | undefined) ?? 0;
    if (r.status === 'APPROVED') used += d; else pending += d;
  }
  const quota = quotaFor(s, type);
  return { type, quota, used, pending, available: quota == null ? null : Math.max(0, quota - used - pending) };
}

export async function allBalances(s: S, employeeId: string, sy: number) {
  return Promise.all(LEAVE_TYPES.map(t => balanceFor(s, employeeId, t, sy)));
}

/** Throws a message if the buckets do not fit in the remaining balance. */
export async function checkQuota(s: S, employeeId: string, type: string, buckets: Record<string, number>, excludeId?: string) {
  const quota = quotaFor(s, type);
  if (quota == null) return null;
  for (const [y, days] of Object.entries(buckets)) {
    const b = await balanceFor(s, employeeId, type, Number(y), excludeId);
    if (days > (b.available ?? 0) + 1e-9) {
      const word = type.toLowerCase();
      return quota === 0 ? `${word} leave is not allowed (quota is 0).`
        : `Not enough ${word} leave: you asked for ${days} day(s) but only ${b.available} day(s) are left for ${leaveYearLabel(Number(y), s.leaveYearStartMonth)} (quota ${quota}, used ${b.used}, pending ${b.pending}).`;
    }
  }
  return null;
}
