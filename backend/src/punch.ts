import { prisma, getSettings } from './db';
import { HttpError, haversineM, cosine, localParts, hhmm } from './util';
import { bestScore, bestOther, validEmbedding, invalidateFaces, updateCachedTemplates } from './faceIndex';
import { consumeChallenge } from './challenge';

export type PunchType = 'IN' | 'OUT' | 'LUNCH_OUT' | 'LUNCH_IN';
export type PunchInput = {
  type: PunchType; lat: number; lng: number; accuracy: number; isMock: boolean;
  nonce: string; frames: number[][]; actionsDone: string[];
};

const ADAPT_MIN_SCORE = 0.78;   // only very confident matches may refresh the stored templates
const ADAPT_MAX_SIM = 0.93;     // ...and only if the new image adds something new
const MAX_TEMPLATES = 12;
const FRAME_CONSISTENCY = 0.55; // the two frames of one punch must be the same person

const mins = (a: Date, b: Date) => Math.max(0, Math.round((a.getTime() - b.getTime()) / 60000));
const isWorkDay = (s: { workDays: string; holidays: string }, date: string, dow: number) =>
  s.workDays.split(',').map(Number).includes(dow) && !s.holidays.split(',').map(x => x.trim()).includes(date);

export async function leaveOn(employeeId: string, date: string) {
  return prisma.leaveRequest.findFirst({ where: { employeeId, status: 'APPROVED', fromDate: { lte: date }, toDate: { gte: date } } });
}

async function logAttempt(employeeId: string, type: string, ok: boolean, reason: string, score: number, otherScore: number) {
  await prisma.faceAttempt.create({ data: { employeeId, type, ok, reason, score: Number(score.toFixed(3)), otherScore: Number(otherScore.toFixed(3)) } });
}

/**
 * Face decision, strictest-first:
 * 1. challenge actions done, 2. frames are real embeddings and the same person, 3. the LOWEST frame score meets the threshold,
 * 4. no other employee matches as well (look-alike / someone else's face).
 */
async function verifyFace(emp: { id: string; faceData: string; faceEnrollCount: number }, p: PunchInput, s: { faceThreshold: number; faceMargin: number }) {
  const expected = consumeChallenge(p.nonce, emp.id, p.type);
  if (JSON.stringify(expected) !== JSON.stringify(p.actionsDone)) {
    await logAttempt(emp.id, p.type, false, 'LIVENESS_FAILED', 0, 0);
    throw new HttpError(403, 'LIVENESS_FAILED', 'Liveness check failed. Do the requested actions (blink, turn head, smile) and try again.');
  }
  if (p.frames.length !== 2 || !p.frames.every(validEmbedding)) throw new HttpError(400, 'BAD_FACE_DATA', 'Face data was invalid. Please try again.');
  if (cosine(p.frames[0], p.frames[1]) < FRAME_CONSISTENCY) {
    await logAttempt(emp.id, p.type, false, 'FRAMES_INCONSISTENT', 0, 0);
    throw new HttpError(403, 'FACE_INCONSISTENT', 'The face changed during the check. Please try again with only you in view.');
  }
  const templates: number[][] = JSON.parse(emp.faceData);
  const scores = p.frames.map(f => bestScore(templates, f));
  const score = Math.min(...scores);
  const other = await bestOther(emp.id, p.frames);

  if (other.score >= s.faceThreshold && other.score > score) {
    await logAttempt(emp.id, p.type, false, `LOOKS_LIKE_OTHER:${other.id}`, score, other.score);
    throw new HttpError(403, 'FACE_OTHER_PERSON', 'This face matches a different employee. Each person must punch with their own account.');
  }
  if (score < s.faceThreshold) {
    await logAttempt(emp.id, p.type, false, 'MISMATCH', score, other.score);
    throw new HttpError(403, 'FACE_MISMATCH', 'Face did not match. Face the camera in good light and try again.');
  }
  if (other.score >= s.faceThreshold && other.score > score - s.faceMargin) {
    await logAttempt(emp.id, p.type, false, `AMBIGUOUS:${other.id}`, score, other.score);
    throw new HttpError(403, 'FACE_AMBIGUOUS', 'Your face is too similar to another employee to be sure. Try again in better light; if it keeps failing, contact the owner.');
  }
  await logAttempt(emp.id, p.type, true, '', score, other.score);

  // very confident match: remember this look so slow changes (beard, glasses, age) keep matching
  if (score >= ADAPT_MIN_SCORE && bestScore(templates, p.frames[0]) < ADAPT_MAX_SIM) {
    const next = [...templates, p.frames[0]];
    if (next.length > MAX_TEMPLATES) next.splice(Math.min(emp.faceEnrollCount || templates.length, MAX_TEMPLATES - 1), 1);
    await prisma.employee.update({ where: { id: emp.id }, data: { faceData: JSON.stringify(next) } });
    await updateCachedTemplates(emp.id, next);
  }
  return { score, other: other.score };
}

export async function processPunch(employeeId: string, p: PunchInput) {
  const s = await getSettings();
  const emp = await prisma.employee.findUniqueOrThrow({ where: { id: employeeId } });
  if (!emp.active) throw new HttpError(403, 'INACTIVE', 'Your account is deactivated');
  if (emp.faceStatus === 'PENDING') throw new HttpError(409, 'FACE_PENDING', 'Your face registration is waiting for the owner to approve it.');
  if (emp.faceStatus !== 'REGISTERED') throw new HttpError(409, 'FACE_NOT_REGISTERED', 'Register your face first');
  if (s.officeLat == null || s.officeLng == null) throw new HttpError(409, 'LOCATION_NOT_SET', 'Owner has not set the office location yet');

  if (p.isMock) throw new HttpError(403, 'MOCK_LOCATION', 'Fake GPS detected. Turn off mock location apps.');
  if (p.accuracy > s.maxAccuracyM) throw new HttpError(422, 'GPS_ACCURACY', `GPS signal is weak (±${Math.round(p.accuracy)} m). Please retry.`);
  const dist = haversineM(p.lat, p.lng, s.officeLat, s.officeLng);
  if (dist > s.radiusM) throw new HttpError(403, 'OUTSIDE_GEOFENCE', `You are ${Math.round(dist)} m from the office (allowed ${s.radiusM} m).`);

  // the server's own clock is the only clock
  const when = new Date();
  const { date, minutes, dow } = localParts(when, s.timezone);

  const leave = await leaveOn(employeeId, date);
  if (leave && !leave.halfDay)
    throw new HttpError(409, 'ON_LEAVE', 'You are on approved leave today. Ask the owner to cancel the leave if you are working.');
  // half-day leave: the workday is split at the lunch window. Morning off -> expected from lunch end; afternoon off -> expected until lunch start.
  let start = hhmm(s.workStart), end = hhmm(s.workEnd);
  const halfLeave = leave?.halfDay ? leave.halfSession : '';
  if (halfLeave === 'FIRST') start = hhmm(s.lunchEnd);
  if (halfLeave === 'SECOND') end = hhmm(s.lunchStart);

  // state rules first (cheap, and the employee is not asked to scan a face for a punch that cannot happen)
  const today = await prisma.attendance.findUnique({ where: { employeeId_date: { employeeId, date } } });
  if (p.type === 'IN') {
    if (today?.punchIn) throw new HttpError(409, 'ALREADY_IN', 'You have already punched in today.');
  } else {
    if (!today?.punchIn) throw new HttpError(409, 'NOT_IN', 'Punch in first.');
    if (today.punchOut) throw new HttpError(409, 'ALREADY_OUT', 'You have already punched out today.');
    if (p.type === 'LUNCH_OUT') {
      if (today.lunchOut) throw new HttpError(409, 'LUNCH_ALREADY', 'You have already taken your lunch break today.');
      if (minutes < hhmm(s.lunchStart) || minutes > hhmm(s.lunchEnd))
        throw new HttpError(409, 'LUNCH_WINDOW', `Lunch break is allowed between ${s.lunchStart} and ${s.lunchEnd}.`);
    }
    if (p.type === 'LUNCH_IN') {
      if (!today.lunchOut) throw new HttpError(409, 'NO_LUNCH_OUT', 'You have not started a lunch break.');
      if (today.lunchIn) throw new HttpError(409, 'LUNCH_DONE', 'You are already back from lunch.');
    }
  }

  const { score } = await verifyFace(emp, p, s);
  let rec;

  if (p.type === 'IN') {
    const late = Math.max(0, minutes - start - s.graceMinutes);
    const data = { punchIn: when, status: late > 0 ? 'LATE' : 'PRESENT', lateMinutes: late, inLat: p.lat, inLng: p.lng, inScore: score, halfLeave };
    rec = today
      ? await prisma.attendance.update({ where: { id: today.id }, data })
      : await prisma.attendance.create({ data: { employeeId, date, ...data } });
  } else if (p.type === 'LUNCH_OUT') {
    rec = await prisma.attendance.update({ where: { id: today!.id }, data: { lunchOut: when } });
  } else if (p.type === 'LUNCH_IN') {
    const taken = mins(when, today!.lunchOut!);
    rec = await prisma.attendance.update({ where: { id: today!.id }, data: { lunchIn: when, lunchTakenMinutes: taken, lunchOverMinutes: Math.max(0, taken - s.lunchMinutes) } });
  } else {
    // OUT. Still on lunch? count the break up to now and leave a note (never block someone from going home)
    let lunchData = {};
    let lunchTaken = today!.lunchTakenMinutes;
    if (today!.lunchOut && !today!.lunchIn) {
      lunchTaken = mins(when, today!.lunchOut);
      lunchData = { lunchTakenMinutes: lunchTaken, lunchOverMinutes: Math.max(0, lunchTaken - s.lunchMinutes), note: (today!.note ? today!.note + ' | ' : '') + 'Punched out while on lunch break' };
    }
    rec = await prisma.attendance.update({
      where: { id: today!.id },
      data: { punchOut: when, earlyMinutes: Math.max(0, end - minutes), workedMinutes: Math.max(0, mins(when, today!.punchIn!) - lunchTaken), outLat: p.lat, outLng: p.lng, outScore: score, ...lunchData },
    });
  }
  return { ok: true, attendance: rec, distanceM: Math.round(dist), score: Number(score.toFixed(3)), nonWorkingDay: !isWorkDay(s, date, dow) };
}

// Every active employee with no record on a working day: LEAVE if approved leave covers it, otherwise ABSENT.
export async function markAbsentees(forDate?: string) {
  const s = await getSettings();
  const lp = localParts(forDate ? new Date(forDate + 'T12:00:00Z') : new Date(), s.timezone);
  const date = forDate ?? lp.date;
  if (!isWorkDay(s, date, lp.dow)) return 0;
  const emps = await prisma.employee.findMany({ where: { active: true }, include: { attendance: { where: { date } } } });
  let n = 0;
  for (const e of emps) {
    if (e.attendance.length) continue;
    const onLeave = await leaveOn(e.id, date);
    await prisma.attendance.create({ data: onLeave && !onLeave.halfDay
      ? { employeeId: e.id, date, status: 'LEAVE', note: 'Approved leave' }
      : { employeeId: e.id, date, status: 'ABSENT', note: onLeave ? 'Half-day leave, but no punch in' : 'Auto: no punch in', halfLeave: onLeave?.halfSession ?? '' } });
    n++;
  }
  return n;
}

// dates (org-local) between two YYYY-MM-DD strings, inclusive
export function eachDate(from: string, to: string) {
  const out: string[] = [];
  for (let d = new Date(from + 'T00:00:00Z'); d <= new Date(to + 'T00:00:00Z'); d = new Date(d.getTime() + 86400000)) out.push(d.toISOString().slice(0, 10));
  return out;
}

// Apply an approved leave to days that are already today or in the past (future days are handled by the nightly job)
export async function applyLeaveRows(employeeId: string, from: string, to: string) {
  const s = await getSettings();
  const today = localParts(new Date(), s.timezone).date;
  for (const date of eachDate(from, to)) {
    if (date > today) break;
    const dow = new Date(date + 'T00:00:00Z').getUTCDay();
    if (!isWorkDay(s, date, dow)) continue;
    const ex = await prisma.attendance.findUnique({ where: { employeeId_date: { employeeId, date } } });
    if (ex?.punchIn) continue; // they actually worked that day: keep the real punches
    if (ex) await prisma.attendance.update({ where: { id: ex.id }, data: { status: 'LEAVE', note: 'Approved leave', manual: false } });
    else await prisma.attendance.create({ data: { employeeId, date, status: 'LEAVE', note: 'Approved leave' } });
  }
}
