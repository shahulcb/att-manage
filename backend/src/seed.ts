import './env';
import { prisma, getSettings } from './db';
import { ensureOwner } from './bootstrap';
import { DEMO_EMPLOYEES } from './demoData';
import bcrypt from 'bcryptjs';
import { randomBytes } from 'node:crypto';
import { localParts, hhmm } from './util';
import { countLeaveDays } from './leave';

const rnd = (a: number, b: number) => Math.floor(a + Math.random() * (b - a + 1));

// org-local date + minutes-of-day -> UTC Date
function toUtc(date: string, minutes: number, tz: string) {
  const guess = new Date(`${date}T${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}:00Z`);
  const lp = localParts(guess, tz);
  const diff = minutes - lp.minutes + (lp.date === date ? 0 : lp.date > date ? -1440 : 1440);
  return new Date(guess.getTime() + diff * 60000);
}

const readable = (n: number) => { const c = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; return Array.from(randomBytes(n), b => c[b % c.length]).join(''); };

(async () => {
  await ensureOwner();
  let s = await getSettings();
  // never overwrite settings that someone already changed: only fill in an empty office location
  if (s.officeLat == null) {
    s = await prisma.settings.update({ where: { id: 'main' }, data: { orgName: 'Demo Company', officeLat: 12.9716, officeLng: 77.5946 } }); // placeholder: set the real one in the owner app
  }

  // the owner keeps their password, except when it is still the well-known default: then give them a fresh one
  const created: string[] = [];
  const owner = await prisma.user.findFirst({ where: { role: 'OWNER' } });
  let ownerPw = '';
  if (owner && (await bcrypt.compare('owner123', owner.passwordHash))) {
    ownerPw = process.env.SEED_OWNER_PASSWORD || readable(14);
    await prisma.user.update({ where: { id: owner.id }, data: { passwordHash: await bcrypt.hash(ownerPw, 10) } });
  }

  const sharedPw = process.env.SEED_PASSWORD || readable(10);
  const hash = await bcrypt.hash(sharedPw, 10);
  const emps: { id: string }[] = [];
  for (const m of DEMO_EMPLOYEES) {
    const e = await prisma.employee.upsert({
      where: { externalId: m.id }, update: {},
      create: { externalId: m.id, name: m.name, email: m.email, phone: m.phone, department: m.department },
    });
    emps.push(e);
    if (!(await prisma.user.findUnique({ where: { username: m.username } }))) {
      await prisma.user.create({ data: { username: m.username, passwordHash: hash, role: 'EMPLOYEE', employeeId: e.id } });
      created.push(m.username);
    }
  }

  // ~3 weeks of random attendance (skips today and non-working days)
  const start = hhmm(s.workStart), end = hhmm(s.workEnd), days = s.workDays.split(',').map(Number);
  let rows = 0;
  for (let back = 1; back <= 21; back++) {
    const d = new Date(Date.now() - back * 86400000);
    const { date, dow } = localParts(d, s.timezone);
    if (!days.includes(dow)) continue;
    for (const e of emps) {
      const r = Math.random();
      if (r < 0.06) continue; // no record (looks like a missed day in the past)
      if (r < 0.12) { await prisma.attendance.upsert({ where: { employeeId_date: { employeeId: e.id, date } }, update: {}, create: { employeeId: e.id, date, status: 'ABSENT', note: 'Auto: no punch in' } }); rows++; continue; }
      const inM = start + rnd(-20, 40), outM = end + rnd(-45, 40);
      const late = Math.max(0, inM - start - s.graceMinutes), early = Math.max(0, end - outM);
      const pin = toUtc(date, inM, s.timezone), pout = toUtc(date, outM, s.timezone);
      const lunchOutM = hhmm(s.lunchStart) + rnd(0, 20), taken = rnd(35, 75);
      const lo = toUtc(date, lunchOutM, s.timezone), li = toUtc(date, lunchOutM + taken, s.timezone);
      const data = { lunchOut: lo, lunchIn: li, lunchTakenMinutes: taken, lunchOverMinutes: Math.max(0, taken - s.lunchMinutes), punchIn: pin, punchOut: pout, status: late > 0 ? 'LATE' : 'PRESENT', lateMinutes: late, earlyMinutes: early, workedMinutes: Math.max(0, Math.round((pout.getTime() - pin.getTime()) / 60000) - taken), inLat: s.officeLat, inLng: s.officeLng, outLat: s.officeLat, outLng: s.officeLng };
      await prisma.attendance.upsert({ where: { employeeId_date: { employeeId: e.id, date } }, update: {}, create: { employeeId: e.id, date, ...data } });
      rows++;
    }
  }

  // a few pending leave requests so the owner has something to review (older demo rows without day counts are replaced)
  await prisma.leaveRequest.deleteMany({ where: { status: 'PENDING', reason: { in: ['Family function', 'Fever, doctor appointment', 'Doctor appointment'] } } });
  if ((await prisma.leaveRequest.count({ where: { reason: { in: ['Family function', 'Doctor appointment'] } } })) === 0) {
    const wd = s.workDays.split(',').map(Number);
    const day = (n: number) => { let k = n; while (!wd.includes(localParts(new Date(Date.now() + k * 86400000), s.timezone).dow)) k++; return localParts(new Date(Date.now() + k * 86400000), s.timezone).date; };
    const mk = (i: number, from: string, to: string, type: string, reason: string, half = '') => {
      const c = countLeaveDays(s, from, to, !!half);
      return { employeeId: emps[i].id, fromDate: from, toDate: to, type, reason, halfDay: !!half, halfSession: half, days: c.total, daysJson: JSON.stringify(c.buckets) };
    };
    await prisma.leaveRequest.createMany({ data: [
      mk(3, day(5), day(6), 'CASUAL', 'Family function'),
      mk(4, day(2), day(2), 'SICK', 'Doctor appointment', 'FIRST'),
    ] });
  }

  console.log(`Seeded: owner + settings + ${emps.length} employees + ${rows} attendance rows`);
  console.log(`Accounts created now: ${created.length ? created.join(', ') : 'none (all already existed; their passwords were not changed)'}`);
  if (created.length) console.log(`Password for those ${created.length} employee accounts: ${sharedPw}`);
  if (ownerPw) console.log(`Owner account "${owner!.username}" password was reset to: ${ownerPw}`);
  else console.log('Owner account password unchanged.');
  await prisma.$disconnect();
})().catch(e => { console.error(e); process.exit(1); });
