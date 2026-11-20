import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { prisma, getSettings, audit } from './db';
import { requireRole, sign, uid } from './auth';
import { HttpError, wrap, localParts, hhmm } from './util';
import { erpLogin, checkLoginAllowed, recordLoginFail, clearLoginFails } from './erp';
import { processPunch, markAbsentees, leaveOn, eachDate, applyLeaveRows } from './punch';
import { issueChallenge } from './challenge';
import { bestScore, bestOther, validEmbedding, invalidateFaces } from './faceIndex';
import { cosine } from './util';
import { countLeaveDays, checkQuota, allBalances, balanceFor, leaveYearOf, leaveYearLabel, LEAVE_TYPES } from './leave';
import { MOCK_EMPLOYEES, MOCK_OWNER, MOCK_EMP_PASSWORD, MOCK_OWNER_PASSWORD } from './mockData';

export const router = Router();
const owner = requireRole('owner'), emp = requireRole('employee');

const maskSettings = (s: any) => ({ ...s, erpLoginHeaders: s.erpLoginHeaders && s.erpLoginHeaders !== '{}' ? '********' : '{}' });
const publicEmp = (e: any) => ({ id: e.id, externalId: e.externalId, name: e.name, email: e.email, phone: e.phone, department: e.department, active: e.active, faceStatus: e.faceStatus, faceNote: e.faceNote });
const publicCfg = (s: any) => ({ leaveQuotaEnabled: s.leaveQuotaEnabled, leaveYearStartMonth: s.leaveYearStartMonth, lunchStart: s.lunchStart, lunchEnd: s.lunchEnd, lunchMinutes: s.lunchMinutes, orgName: s.orgName, officeLat: s.officeLat, officeLng: s.officeLng, radiusM: s.radiusM, workStart: s.workStart, workEnd: s.workEnd, graceMinutes: s.graceMinutes, workDays: s.workDays, timezone: s.timezone, maxAccuracyM: s.maxAccuracyM });

// ---------- auth ----------
// One login form. Credentials are verified by the main ERP; the ERP role decides Owner vs Employee.
router.post('/auth/login', wrap(async (req, res) => {
  const b = z.object({ identifier: z.string().min(1).max(200), password: z.string().min(1).max(200) }).parse(req.body);
  const key = `${req.ip}|${b.identifier.toLowerCase()}`;
  checkLoginAllowed(key);

  const localOwner = async () => {
    const o = await prisma.owner.findUnique({ where: { username: b.identifier } });
    return o && (await bcrypt.compare(b.password, o.passwordHash)) ? o : null;
  };

  let user;
  try { user = await erpLogin(b.identifier, b.password); }
  catch (e: any) {
    // break-glass: local owner account works if the ERP is down / not configured
    if (e instanceof HttpError && ['BAD_CREDENTIALS', 'ERP_UNAVAILABLE', 'ERP_NOT_CONFIGURED'].includes(e.code)) {
      const o = await localOwner();
      if (o) { clearLoginFails(key); return res.json({ token: sign({ role: 'owner', id: o.id }), role: 'owner', name: 'Owner' }); }
      if (e.code === 'BAD_CREDENTIALS') recordLoginFail(key);
    }
    throw e;
  }
  clearLoginFails(key);
  if (!user.active) throw new HttpError(403, 'INACTIVE', 'Your account is deactivated in the company system.');
  if (user.isOwner) return res.json({ token: sign({ role: 'owner', id: 'erp:' + user.externalId }), role: 'owner', name: user.name });

  // employee: create on first login, keep profile in sync with ERP
  const e = await prisma.employee.upsert({
    where: { externalId: user.externalId },
    update: { name: user.name, email: user.email, department: user.department, active: true },
    create: { externalId: user.externalId, name: user.name, email: user.email, department: user.department },
  });
  res.json({ token: sign({ role: 'employee', id: e.id }), role: 'employee', name: e.name });
}));

// ---------- employee ----------
router.get('/me', emp, wrap(async (req, res) => {
  const e = await prisma.employee.findUniqueOrThrow({ where: { id: uid(req) } });
  if (!e.active) throw new HttpError(403, 'INACTIVE', 'Your account is deactivated');
  const pending = await prisma.faceResetRequest.findFirst({ where: { employeeId: e.id, status: 'PENDING' } });
  res.json({ ...publicEmp(e), faceResetPending: !!pending, config: publicCfg(await getSettings()) });
}));

router.get('/me/today', emp, wrap(async (req, res) => {
  const s = await getSettings();
  const date = localParts(new Date(), s.timezone).date;
  const leave = await leaveOn(uid(req), date);
  res.json({
    date, onLeave: !!leave && !leave.halfDay, halfLeave: leave?.halfDay ? leave.halfSession : null, holiday: s.holidays.split(',').map(x => x.trim()).includes(date),
    attendance: await prisma.attendance.findUnique({ where: { employeeId_date: { employeeId: uid(req), date } } }),
  });
}));

router.get('/me/attendance', emp, wrap(async (req, res) => {
  const month = z.string().regex(/^\d{4}-\d{2}$/).parse(req.query.month);
  res.json(await prisma.attendance.findMany({ where: { employeeId: uid(req), date: { startsWith: month } }, orderBy: { date: 'asc' } }));
}));

const REG_MIN_SAMPLES = 4;
router.post('/me/face/register', emp, wrap(async (req, res) => {
  const b = z.object({
    embeddings: z.array(z.array(z.number())).min(REG_MIN_SAMPLES, `Need at least ${REG_MIN_SAMPLES} face samples`).max(10),
    photo: z.string().max(120000).default(''), // small base64 JPEG thumbnail for the owner to verify
  }).parse(req.body);
  const e = await prisma.employee.findUniqueOrThrow({ where: { id: uid(req) } });
  if (e.faceStatus === 'PENDING') throw new HttpError(409, 'FACE_PENDING', 'Your registration is already waiting for owner approval.');
  if (e.faceStatus === 'REGISTERED') throw new HttpError(409, 'FACE_EXISTS', 'Face already registered. Request a reset from the owner.');
  if (!b.embeddings.every(validEmbedding)) throw new HttpError(400, 'BAD_FACE_DATA', 'Face data was invalid. Please try again.');

  // all samples must be the same person (catches someone stepping in/out of frame, or a bad capture)
  let sum = 0, n = 0, min = 1;
  for (let i = 0; i < b.embeddings.length; i++) for (let j = i + 1; j < b.embeddings.length; j++) { const c = cosine(b.embeddings[i], b.embeddings[j]); sum += c; n++; min = Math.min(min, c); }
  if (sum / n < 0.5 || min < 0.3)
    throw new HttpError(422, 'REGISTRATION_INCONSISTENT', 'The photos did not look like the same person or were too different. Stay alone in the frame, in steady light, and try again.');

  // does this face already belong to someone else? (same person with two accounts, or impersonation)
  const other = await bestOther(e.id, b.embeddings);
  const similar = other.score >= 0.6;
  await prisma.employee.update({ where: { id: e.id }, data: {
    faceData: JSON.stringify(b.embeddings), faceEnrollCount: b.embeddings.length, facePhoto: b.photo, faceNote: '', faceStatus: 'PENDING', faceSubmittedAt: new Date(),
    faceSimilarTo: similar ? other.name : '', faceSimilarScore: similar ? Number(other.score.toFixed(3)) : 0,
  } });
  await audit('FACE_SUBMITTED', { employeeId: e.id, similarTo: similar ? other.name : null, score: other.score });
  res.json({ ok: true, status: 'PENDING' });
}));

router.get('/me/punch-challenge', emp, wrap(async (req, res) => {
  const type = z.enum(['IN', 'OUT', 'LUNCH_OUT', 'LUNCH_IN']).parse(req.query.type);
  res.json(issueChallenge(uid(req), type));
}));

router.post('/me/face/reset-request', emp, wrap(async (req, res) => {
  const b = z.object({ reason: z.string().max(300).default('') }).parse(req.body);
  const cur = await prisma.employee.findUniqueOrThrow({ where: { id: uid(req) } });
  if (cur.faceStatus !== 'REGISTERED') throw new HttpError(409, 'NOT_REGISTERED', cur.faceStatus === 'PENDING' ? 'Your registration is still waiting for approval.' : 'You have no approved face to reset. Register your face instead.');
  const open = await prisma.faceResetRequest.findFirst({ where: { employeeId: uid(req), status: 'PENDING' } });
  if (open) throw new HttpError(409, 'ALREADY_REQUESTED', 'A request is already pending.');
  await prisma.faceResetRequest.create({ data: { employeeId: uid(req), reason: b.reason } });
  res.json({ ok: true });
}));

const punchSchema = z.object({
  type: z.enum(['IN', 'OUT', 'LUNCH_OUT', 'LUNCH_IN']), lat: z.number(), lng: z.number(), accuracy: z.number(), isMock: z.boolean().default(false),
  nonce: z.string().min(8).max(64), frames: z.array(z.array(z.number())).length(2), actionsDone: z.array(z.string()).max(5),
});
router.post('/punch', emp, wrap(async (req, res) => res.json(await processPunch(uid(req), punchSchema.parse(req.body)))));

// ---------- employee leave ----------
const dateStr = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => !isNaN(new Date(v + 'T00:00:00Z').getTime()), 'invalid date');
router.get('/me/leaves', emp, wrap(async (req, res) => {
  res.json(await prisma.leaveRequest.findMany({ where: { employeeId: uid(req) }, orderBy: { createdAt: 'desc' }, take: 100 }));
}));
router.get('/me/leave-balance', emp, wrap(async (req, res) => {
  const s = await getSettings();
  const sy = leaveYearOf(localParts(new Date(), s.timezone).date, s.leaveYearStartMonth);
  res.json({ quotaEnabled: s.leaveQuotaEnabled, year: leaveYearLabel(sy, s.leaveYearStartMonth), balances: await allBalances(s, uid(req), sy) });
}));
router.post('/me/leaves', emp, wrap(async (req, res) => {
  const b = z.object({
    fromDate: dateStr, toDate: dateStr, type: z.enum(LEAVE_TYPES).default('CASUAL'), reason: z.string().trim().min(3, 'Please give a reason').max(500),
    halfDay: z.boolean().default(false), halfSession: z.enum(['FIRST', 'SECOND']).optional(),
  }).parse(req.body);
  const s = await getSettings();
  const today = localParts(new Date(), s.timezone).date;
  if (b.toDate < b.fromDate) throw new HttpError(400, 'VALIDATION', 'End date is before the start date');
  if (b.halfDay && b.fromDate !== b.toDate) throw new HttpError(400, 'VALIDATION', 'A half-day leave must be a single day');
  if (b.halfDay && !b.halfSession) throw new HttpError(400, 'VALIDATION', 'Choose which half of the day you are off (first or second)');
  if (eachDate(b.fromDate, b.toDate).length > 60) throw new HttpError(400, 'VALIDATION', 'A leave request can cover at most 60 days');
  if (b.fromDate < new Date(new Date(today + 'T00:00:00Z').getTime() - 7 * 86400000).toISOString().slice(0, 10)) throw new HttpError(400, 'VALIDATION', 'You cannot request leave for dates more than 7 days in the past');
  const { total, buckets } = countLeaveDays(s, b.fromDate, b.toDate, b.halfDay);
  if (total === 0) throw new HttpError(400, 'NO_WORKING_DAYS', 'The selected dates are holidays or non-working days, so no leave is needed.');
  const overlap = await prisma.leaveRequest.findFirst({ where: { employeeId: uid(req), status: { in: ['PENDING', 'APPROVED'] }, fromDate: { lte: b.toDate }, toDate: { gte: b.fromDate } } });
  if (overlap) throw new HttpError(409, 'LEAVE_OVERLAP', `You already have a ${overlap.status.toLowerCase()} leave from ${overlap.fromDate} to ${overlap.toDate} that overlaps.`);
  const worked = await prisma.attendance.findFirst({ where: { employeeId: uid(req), date: { gte: b.fromDate, lte: b.toDate }, punchIn: { not: null } } });
  if (worked && !b.halfDay) throw new HttpError(409, 'ALREADY_WORKED', `You already punched in on ${worked.date}. Choose other dates.`);
  const quotaMsg = await checkQuota(s, uid(req), b.type, buckets);
  if (quotaMsg) throw new HttpError(409, 'QUOTA_EXCEEDED', quotaMsg);
  res.json(await prisma.leaveRequest.create({ data: {
    employeeId: uid(req), fromDate: b.fromDate, toDate: b.toDate, type: b.type, reason: b.reason,
    halfDay: b.halfDay, halfSession: b.halfDay ? b.halfSession! : '', days: total, daysJson: JSON.stringify(buckets),
  } }));
}));
router.post('/me/leaves/:id/cancel', emp, wrap(async (req, res) => {
  const l = await prisma.leaveRequest.findFirst({ where: { id: String(req.params.id), employeeId: uid(req) } });
  if (!l) throw new HttpError(404, 'NOT_FOUND', 'Leave request not found');
  const s = await getSettings();
  const today = localParts(new Date(), s.timezone).date;
  if (l.status === 'APPROVED' && l.fromDate <= today) throw new HttpError(409, 'LEAVE_STARTED', 'This leave has already started. Ask the owner to cancel it.');
  if (!['PENDING', 'APPROVED'].includes(l.status)) throw new HttpError(409, 'NOT_CANCELLABLE', 'This request is already closed.');
  await prisma.leaveRequest.update({ where: { id: l.id }, data: { status: 'CANCELLED', decidedAt: new Date() } });
  res.json({ ok: true });
}));

// ---------- owner ----------
router.get('/owner/dashboard', owner, wrap(async (_req, res) => {
  const s = await getSettings();
  const date = localParts(new Date(), s.timezone).date;
  const [total, rows, pending, pendingLeaves, pendingFaces] = await Promise.all([
    prisma.employee.count({ where: { active: true } }),
    prisma.attendance.findMany({ where: { date } }),
    prisma.faceResetRequest.count({ where: { status: 'PENDING' } }),
    prisma.leaveRequest.count({ where: { status: 'PENDING' } }),
    prisma.employee.count({ where: { faceStatus: 'PENDING', active: true } }),
  ]);
  const present = rows.filter(r => r.punchIn && r.status === 'PRESENT').length;
  const late = rows.filter(r => r.status === 'LATE').length;
  const absent = rows.filter(r => r.status === 'ABSENT').length;
  const onLeave = rows.filter(r => r.status === 'LEAVE').length;
  res.json({ date, totalEmployees: total, present, late, absent, onLeave, notYet: Math.max(0, total - present - late - absent - onLeave), pendingFaceRequests: pending, pendingLeaves, pendingFaceRegistrations: pendingFaces });
}));

router.get('/owner/settings', owner, wrap(async (_req, res) => {
  const s = await getSettings();
  res.json(maskSettings(s));
}));
router.put('/owner/settings', owner, wrap(async (req, res) => {
  const t = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
  const b = z.object({
    orgName: z.string().min(1), officeLat: z.number().min(-90).max(90).nullable(), officeLng: z.number().min(-180).max(180).nullable(),
    radiusM: z.number().int().min(20).max(5000), workStart: t, workEnd: t, graceMinutes: z.number().int().min(0).max(120),
    workDays: z.string().regex(/^[0-6](,[0-6])*$/), timezone: z.string().min(1), maxAccuracyM: z.number().int().min(10).max(500),
    faceThreshold: z.number().min(0.4).max(0.9), faceMargin: z.number().min(0).max(0.2),
    leaveQuotaEnabled: z.boolean(), leaveQuotaCasual: z.number().min(0).max(366).multipleOf(0.5), leaveQuotaSick: z.number().min(0).max(366).multipleOf(0.5), leaveQuotaOther: z.number().min(0).max(366).multipleOf(0.5), leaveYearStartMonth: z.number().int().min(1).max(12),
    lunchStart: t, lunchEnd: t, lunchMinutes: z.number().int().min(5).max(240),
    holidays: z.string().regex(/^(\d{4}-\d{2}-\d{2}(,\s*\d{4}-\d{2}-\d{2})*)?$/, 'Holidays must be YYYY-MM-DD dates separated by commas'),
    erpLoginUrl: z.string(), erpUserField: z.string().min(1), erpPassField: z.string().min(1), erpUserPath: z.string(), erpOwnerRoles: z.string(),
    erpLoginMap: z.string().refine(v => { try { JSON.parse(v); return true; } catch { return false; } }, 'must be JSON'),
    erpLoginHeaders: z.string().refine(v => { try { JSON.parse(v); return true; } catch { return false; } }, 'must be JSON'),
  }).partial().parse(req.body);
  if ((b.workStart || b.workEnd) && hhmm(b.workStart ?? (await getSettings()).workStart) >= hhmm(b.workEnd ?? (await getSettings()).workEnd))
    throw new HttpError(400, 'VALIDATION', 'Work end must be after work start');
  { const cur = await getSettings();
    const ls = b.lunchStart ?? cur.lunchStart, le = b.lunchEnd ?? cur.lunchEnd, ws = b.workStart ?? cur.workStart, we = b.workEnd ?? cur.workEnd;
    if (hhmm(ls) >= hhmm(le)) throw new HttpError(400, 'VALIDATION', 'Lunch end must be after lunch start');
    if (hhmm(ls) < hhmm(ws) || hhmm(le) > hhmm(we)) throw new HttpError(400, 'VALIDATION', 'Lunch window must be inside work hours'); }
  if (b.timezone) { try { new Intl.DateTimeFormat('en', { timeZone: b.timezone }); } catch { throw new HttpError(400, 'VALIDATION', 'Unknown timezone'); } }
  if (b.erpLoginHeaders === '********') delete b.erpLoginHeaders;
  await getSettings();
  const s = await prisma.settings.update({ where: { id: 'main' }, data: b });
  await audit('SETTINGS', Object.keys(b));
  res.json(maskSettings(s));
}));

router.get('/owner/employees', owner, wrap(async (_req, res) => {
  res.json((await prisma.employee.findMany({ orderBy: { name: 'asc' } })).map(publicEmp));
}));
router.post('/owner/employees/:id/reset-face', owner, wrap(async (req, res) => {
  const id = String(req.params.id);
  await prisma.employee.update({ where: { id }, data: { faceData: '[]', facePhoto: '', faceSimilarTo: '', faceSimilarScore: 0, faceEnrollCount: 0, faceNote: '', faceStatus: 'NONE' } });
  invalidateFaces();
  await audit('RESET_FACE', { employeeId: id });
  res.json({ ok: true });
}));

router.get('/owner/face-registrations', owner, wrap(async (_req, res) => {
  const list = await prisma.employee.findMany({ where: { faceStatus: 'PENDING', active: true }, orderBy: { faceSubmittedAt: 'asc' } });
  res.json(list.map(e => ({ ...publicEmp(e), photo: e.facePhoto, submittedAt: e.faceSubmittedAt, similarTo: e.faceSimilarTo, similarScore: e.faceSimilarScore })));
}));
router.post('/owner/face-registrations/:id/:action', owner, wrap(async (req, res) => {
  const action = z.enum(['approve', 'reject']).parse(req.params.action);
  const note = z.object({ note: z.string().max(300).default('') }).parse(req.body ?? {}).note;
  const e = await prisma.employee.findUniqueOrThrow({ where: { id: String(req.params.id) } });
  if (e.faceStatus !== 'PENDING') throw new HttpError(409, 'RESOLVED', 'This registration was already handled');
  if (action === 'approve') {
    await prisma.employee.update({ where: { id: e.id }, data: { faceStatus: 'REGISTERED', faceNote: '' } });
    invalidateFaces();
  } else {
    await prisma.employee.update({ where: { id: e.id }, data: { faceStatus: 'NONE', faceData: '[]', facePhoto: '', faceSimilarTo: '', faceSimilarScore: 0, faceEnrollCount: 0, faceNote: note || 'Registration rejected. Please register again.' } });
  }
  await audit('FACE_REGISTRATION_' + action.toUpperCase(), { employeeId: e.id, note });
  res.json({ ok: true });
}));

router.get('/owner/face-requests', owner, wrap(async (_req, res) => {
  res.json(await prisma.faceResetRequest.findMany({ where: { status: 'PENDING' }, include: { employee: { select: { name: true, externalId: true } } }, orderBy: { createdAt: 'asc' } }));
}));
router.post('/owner/face-requests/:id/:action', owner, wrap(async (req, res) => {
  const action = z.enum(['approve', 'reject']).parse(req.params.action);
  const r = await prisma.faceResetRequest.findUniqueOrThrow({ where: { id: String(req.params.id) } });
  if (r.status !== 'PENDING') throw new HttpError(409, 'RESOLVED', 'Already handled');
  if (action === 'approve') await prisma.employee.update({ where: { id: r.employeeId }, data: { faceData: '[]', facePhoto: '', faceSimilarTo: '', faceSimilarScore: 0, faceEnrollCount: 0, faceNote: '', faceStatus: 'NONE' } });
  if (action === 'approve') invalidateFaces();
  await prisma.faceResetRequest.update({ where: { id: r.id }, data: { status: action === 'approve' ? 'APPROVED' : 'REJECTED', resolvedAt: new Date() } });
  await audit('FACE_REQUEST_' + action.toUpperCase(), { id: r.id });
  res.json({ ok: true });
}));

router.get('/owner/leaves', owner, wrap(async (req, res) => {
  const st = z.enum(['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'ALL']).default('PENDING').parse(req.query.status ?? 'PENDING');
  const s = await getSettings();
  const list = await prisma.leaveRequest.findMany({
    where: st === 'ALL' ? {} : { status: st }, include: { employee: { select: { name: true, externalId: true, department: true } } },
    orderBy: { createdAt: st === 'PENDING' ? 'asc' : 'desc' }, take: 200,
  });
  res.json(await Promise.all(list.map(async l => ({ ...l, balance: await balanceFor(s, l.employeeId, l.type, leaveYearOf(l.fromDate, s.leaveYearStartMonth), l.id) }))));
}));
router.post('/owner/leaves/:id/:action', owner, wrap(async (req, res) => {
  const action = z.enum(['approve', 'reject', 'revoke']).parse(req.params.action);
  const note = z.object({ note: z.string().max(300).default('') }).parse(req.body ?? {}).note;
  const l = await prisma.leaveRequest.findUniqueOrThrow({ where: { id: String(req.params.id) } });
  const s = await getSettings();
  const today = localParts(new Date(), s.timezone).date;
  if (action === 'revoke') {
    if (l.status !== 'APPROVED') throw new HttpError(409, 'RESOLVED', 'Only approved leave can be revoked');
    await prisma.leaveRequest.update({ where: { id: l.id }, data: { status: 'CANCELLED', ownerNote: note, decidedAt: new Date() } });
    // past days that were LEAVE become ABSENT; today/future rows are removed (nothing has happened yet)
    const rows = await prisma.attendance.findMany({ where: { employeeId: l.employeeId, status: 'LEAVE', date: { gte: l.fromDate, lte: l.toDate } } });
    for (const r of rows) {
      if (r.date < today) await prisma.attendance.update({ where: { id: r.id }, data: { status: 'ABSENT', note: 'Leave revoked by owner' } });
      else await prisma.attendance.delete({ where: { id: r.id } });
    }
  } else {
    if (l.status !== 'PENDING') throw new HttpError(409, 'RESOLVED', 'This request was already handled (or cancelled by the employee)');
    if (action === 'reject' && !note.trim()) throw new HttpError(400, 'VALIDATION', 'Please give a reason for rejecting');
    if (action === 'approve') {
      const msg = await checkQuota(s, l.employeeId, l.type, JSON.parse(l.daysJson || '{}'), l.id);
      if (msg) throw new HttpError(409, 'QUOTA_EXCEEDED', msg);
    }
    await prisma.leaveRequest.update({ where: { id: l.id }, data: { status: action === 'approve' ? 'APPROVED' : 'REJECTED', ownerNote: note, decidedAt: new Date() } });
    if (action === 'approve' && !l.halfDay) await applyLeaveRows(l.employeeId, l.fromDate, l.toDate);
  }
  await audit('LEAVE_' + action.toUpperCase(), { id: l.id, note });
  res.json({ ok: true });
}));

router.get('/owner/employees/:id/leave-balance', owner, wrap(async (req, res) => {
  const s = await getSettings();
  const sy = leaveYearOf(localParts(new Date(), s.timezone).date, s.leaveYearStartMonth);
  res.json({ quotaEnabled: s.leaveQuotaEnabled, year: leaveYearLabel(sy, s.leaveYearStartMonth), balances: await allBalances(s, String(req.params.id), sy) });
}));

router.get('/owner/face-attempts', owner, wrap(async (req, res) => {
  const q = z.object({ employeeId: z.string().optional(), failedOnly: z.string().optional(), limit: z.coerce.number().int().min(1).max(200).default(50) }).parse(req.query);
  const rows = await prisma.faceAttempt.findMany({
    where: { ...(q.employeeId ? { employeeId: q.employeeId } : {}), ...(q.failedOnly === 'true' ? { ok: false } : {}) },
    orderBy: { createdAt: 'desc' }, take: q.limit,
  });
  const emps = await prisma.employee.findMany({ where: { id: { in: [...new Set(rows.map(x => x.employeeId))] } }, select: { id: true, name: true, externalId: true } });
  res.json(rows.map(x => ({ ...x, employee: emps.find(e => e.id === x.employeeId) ?? null })));
}));

router.get('/owner/attendance', owner, wrap(async (req, res) => {
  const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).parse(req.query.date);
  const emps = await prisma.employee.findMany({ where: { active: true }, orderBy: { name: 'asc' } });
  const rows = await prisma.attendance.findMany({ where: { date } });
  res.json(emps.map(e => ({ employee: publicEmp(e), attendance: rows.find(r => r.employeeId === e.id) ?? null })));
}));

// manual add / correct (audited)
router.put('/owner/attendance', owner, wrap(async (req, res) => {
  const b = z.object({
    employeeId: z.string().min(1), date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    punchIn: z.string().regex(/^\d{2}:\d{2}$/).nullable(), punchOut: z.string().regex(/^\d{2}:\d{2}$/).nullable(), note: z.string().min(1, 'A reason is required'),
  }).parse(req.body);
  const s = await getSettings();
  const toDate = (hm: string | null) => {
    if (!hm) return null;
    // convert local org time -> UTC by probing the offset
    const guess = new Date(`${b.date}T${hm}:00Z`);
    const lp = localParts(guess, s.timezone);
    const diff = hhmm(hm) - lp.minutes + (lp.date === b.date ? 0 : lp.date > b.date ? -1440 : 1440);
    return new Date(guess.getTime() + diff * 60000);
  };
  const pin = toDate(b.punchIn), pout = toDate(b.punchOut);
  if (pout && !pin) throw new HttpError(400, 'VALIDATION', 'Punch out needs a punch in');
  if (pin && pout && pout <= pin) throw new HttpError(400, 'VALIDATION', 'Punch out must be after punch in');
  const late = b.punchIn ? Math.max(0, hhmm(b.punchIn) - hhmm(s.workStart) - s.graceMinutes) : 0;
  const early = b.punchOut ? Math.max(0, hhmm(s.workEnd) - hhmm(b.punchOut)) : 0;
  const existing = await prisma.attendance.findUnique({ where: { employeeId_date: { employeeId: b.employeeId, date: b.date } } });
  const lunchTaken = existing?.lunchTakenMinutes ?? 0;
  const data = {
    punchIn: pin, punchOut: pout, status: !pin ? 'ABSENT' : late > 0 ? 'LATE' : 'PRESENT', lateMinutes: late, earlyMinutes: early,
    workedMinutes: pin && pout ? Math.max(0, Math.round((pout.getTime() - pin.getTime()) / 60000) - lunchTaken) : 0, manual: true, note: b.note,
  };
  const rec = await prisma.attendance.upsert({
    where: { employeeId_date: { employeeId: b.employeeId, date: b.date } }, update: data, create: { employeeId: b.employeeId, date: b.date, ...data },
  });
  await audit('MANUAL_ATTENDANCE', b);
  res.json(rec);
}));

router.get('/owner/report/monthly', owner, wrap(async (req, res) => res.json(await monthly(String(req.query.month)))));
router.get('/owner/report/export.csv', owner, wrap(async (req, res) => {
  const month = String(req.query.month);
  const rows = await prisma.attendance.findMany({ where: { date: { startsWith: month } }, include: { employee: true }, orderBy: [{ date: 'asc' }, { employeeId: 'asc' }] });
  const s = await getSettings();
  const tm = (d: Date | null) => (d ? (() => { const p = localParts(d, s.timezone).minutes; return `${String(Math.floor(p / 60)).padStart(2, '0')}:${String(p % 60).padStart(2, '0')}`; })() : '');
  const esc = (v: any) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = ['Date,Employee ID,Name,Status,Punch In,Lunch Out,Lunch In,Punch Out,Late (min),Early exit (min),Lunch taken (min),Lunch over (min),Worked (min),Manual,Note',
    ...rows.map(r => [r.date, r.employee.externalId, r.employee.name, r.status, tm(r.punchIn), tm(r.lunchOut), tm(r.lunchIn), tm(r.punchOut), r.lateMinutes, r.earlyMinutes, r.lunchTakenMinutes, r.lunchOverMinutes, r.workedMinutes, r.manual, r.note].map(esc).join(','))].join('\n');
  res.setHeader('Content-Type', 'text/csv').setHeader('Content-Disposition', `attachment; filename="attendance-${month}.csv"`).send(csv);
}));

async function monthly(month: string) {
  if (!/^\d{4}-\d{2}$/.test(month)) throw new HttpError(400, 'VALIDATION', 'month must be YYYY-MM');
  const emps = await prisma.employee.findMany({ where: { active: true }, include: { attendance: { where: { date: { startsWith: month } } } }, orderBy: { name: 'asc' } });
  return emps.map(e => ({
    employee: publicEmp(e),
    present: e.attendance.filter(a => a.status === 'PRESENT').length,
    late: e.attendance.filter(a => a.status === 'LATE').length,
    absent: e.attendance.filter(a => a.status === 'ABSENT').length,
    leave: e.attendance.filter(a => a.status === 'LEAVE').length,
    lunchOver: e.attendance.filter(a => a.lunchOverMinutes > 0).length,
    earlyExits: e.attendance.filter(a => a.earlyMinutes > 0).length,
    missingPunchOut: e.attendance.filter(a => a.punchIn && !a.punchOut).length,
    workedMinutes: e.attendance.reduce((x, a) => x + a.workedMinutes, 0),
  }));
}

router.post('/owner/run-absent-check', owner, wrap(async (req, res) => res.json({ marked: await markAbsentees(req.body?.date) })));

// ---------- MOCK ERP login (stand-in for the real ERP until its API is known) ----------
router.post('/mock-erp/login', (req, res) => {
  const name = String(req.body?.username || '').toLowerCase();
  const pw = req.body?.password;
  const owner = name === MOCK_OWNER.username && pw === MOCK_OWNER_PASSWORD ? MOCK_OWNER : null;
  const emp = MOCK_EMPLOYEES.find(e => e.username === name && pw === MOCK_EMP_PASSWORD);
  const u = owner ?? emp;
  if (!u) return res.status(401).json({ error: 'invalid credentials' });
  res.json({ token: 'mock-erp-session', user: { id: u.id, name: u.name, email: u.email, role: u.role, department: u.department, active: u.active } });
});
