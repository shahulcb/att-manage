import './env';
import assert from 'node:assert/strict';
import { MongoMemoryReplSet } from 'mongodb-memory-server';

const unit = (v: number[]) => { const n = Math.sqrt(v.reduce((a, x) => a + x * x, 0)); return v.map(x => x / n); };
const emb = (seed: number) => unit(Array.from({ length: 192 }, (_, i) => Math.sin(i * seed + seed)));
const mix = (a: number[], b: number[], w: number) => unit(a.map((x, i) => x + w * b[i])); // vector at a known distance from a
const reg = (e: number[] | number, n = 6) => Array.from({ length: n }, () => (typeof e === 'number' ? emb(e) : e));
let base = '', tok = '';
async function punchCall(b: any, token: string) {
  const ch = await call('GET', `/me/punch-challenge?type=${b.type}`, undefined, token);
  const { embedding, frames, actions, nonce, ...rest } = b;
  return call('POST', '/punch', { ...rest, nonce: nonce ?? ch.json.nonce, frames: frames ?? [embedding, embedding], actionsDone: actions ?? ch.json.actions }, token);
}
async function call(method: string, path: string, body?: any, token?: string) {
  const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let json: any; try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
}

(async () => {
  // isolated throw-away database: never touches the real one
  const mongo = await MongoMemoryReplSet.create({ replSet: { count: 1 } });
  process.env.DATABASE_URL = mongo.getUri('attendance_test');
  const { execSync } = await import('node:child_process');
  execSync('npx prisma db push --skip-generate --accept-data-loss', { stdio: 'ignore', env: process.env });
  const { app } = await import('./index');
  const { prisma } = await import('./db');
  const { ensureOwner } = await import('./bootstrap');
  await ensureOwner();
  const srv = app.listen(0); base = `http://localhost:${(srv.address() as any).port}/api`;

  // ---- accounts live in the User collection ----
  assert.equal((await call('POST', '/auth/login', { identifier: 'asha', password: 'Pass1234' })).json.code, 'BAD_CREDENTIALS', 'unknown user');
  const o = await call('POST', '/auth/login', { identifier: 'owner', password: 'owner123' }); // dev default owner
  assert.equal(o.status, 200); const ot = o.json.token;
  assert.equal((await call('POST', '/auth/login', { identifier: 'OWNER', password: 'owner123' })).status, 200, 'usernames are case-insensitive');
  assert.equal((await call('POST', '/auth/login', { identifier: 'owner', password: 'wrong' })).json.code, 'BAD_CREDENTIALS');
  assert.equal(await prisma.user.count({ where: { role: 'OWNER' } }), 1);
  await call('PUT', '/owner/settings', { officeLat: 12.9716, officeLng: 77.5946, radiusM: 100, workStart: '00:00', workEnd: '23:59', graceMinutes: 0, workDays: '0,1,2,3,4,5,6', lunchStart: '00:00', lunchEnd: '00:01', lunchMinutes: 60 }, ot);

  // owner creates employees (profile + sign-in account)
  const bcrypt = (await import('bcryptjs')).default;
  const { DEMO_EMPLOYEES } = await import('./demoData');
  const mk = await call('POST', '/owner/employees', { name: 'Asha Kumar', username: 'Asha', password: 'Pass1234', department: 'Sales' }, ot);
  assert.equal(mk.status, 200, JSON.stringify(mk.json)); assert.equal(mk.json.username, 'asha'); assert.equal(mk.json.employee.externalId, 'E001', 'next employee id is automatic');
  assert.equal(mk.json.password, undefined, 'a password the owner typed is not echoed back');
  assert.equal((await call('POST', '/owner/employees', { name: 'Dup', username: 'asha', password: 'Pass1234' }, ot)).json.code, 'USERNAME_TAKEN');
  assert.equal((await call('POST', '/owner/employees', { name: 'Short', username: 'shorty', password: '123' }, ot)).status, 400, 'password too short');
  assert.equal((await call('POST', '/owner/employees', { name: 'Bad Name', username: 'a b', password: 'Pass1234' }, ot)).status, 400, 'username characters');
  assert.equal((await call('POST', '/owner/employees', { name: 'Same Id', username: 'sameid', password: 'Pass1234', externalId: 'E001' }, ot)).json.code, 'ID_TAKEN');
  assert.equal((await call('POST', '/owner/employees', { name: 'Nobody', username: 'nobody', password: 'Pass1234' }, tok)).status, 401, 'employees cannot create accounts');
  // the rest of the demo staff, straight into the database (as the seed script does)
  for (const m of DEMO_EMPLOYEES.filter(x => x.username !== 'asha')) {
    const e = await prisma.employee.create({ data: { externalId: m.id, name: m.name, email: m.email, department: m.department } });
    await prisma.user.create({ data: { username: m.username, passwordHash: await bcrypt.hash('Pass1234', 4), role: 'EMPLOYEE', employeeId: e.id } });
  }
  assert.equal((await call('POST', '/owner/sync', {}, ot)).status, 404, 'manual sync endpoint is gone');
  assert.equal((await call('POST', '/auth/login', { identifier: 'boss', password: 'admin123' })).json.code, 'BAD_CREDENTIALS', 'there are no built-in demo accounts');
  assert.equal((await call('GET', '/mock-erp/login')).status, 404, 'mock ERP is gone');

  // generated passwords, reset and deactivate
  const gen = await call('POST', '/owner/employees', { name: 'Temp Person', username: 'temp.person' }, ot);
  assert.equal(gen.status, 200); assert.equal(gen.json.password.length, 10, 'a generated password is shown once');
  assert.equal((await call('POST', '/auth/login', { identifier: 'temp.person', password: gen.json.password })).status, 200);
  const rp = await call('POST', `/owner/employees/${gen.json.employee.id}/reset-password`, {}, ot);
  assert.equal(rp.status, 200); assert.notEqual(rp.json.password, gen.json.password);
  assert.equal((await call('POST', '/auth/login', { identifier: 'temp.person', password: gen.json.password })).json.code, 'BAD_CREDENTIALS', 'old password stops working');
  assert.equal((await call('POST', '/auth/login', { identifier: 'temp.person', password: rp.json.password })).status, 200);
  assert.equal((await call('POST', `/owner/employees/${gen.json.employee.id}/active`, { active: false }, ot)).status, 200);
  assert.equal((await call('POST', '/auth/login', { identifier: 'temp.person', password: rp.json.password })).json.code, 'INACTIVE', 'deactivated accounts cannot sign in');
  assert.equal((await call('POST', `/owner/employees/${gen.json.employee.id}/active`, { active: true }, ot)).status, 200);
  assert.equal((await call('POST', '/auth/login', { identifier: 'temp.person', password: rp.json.password })).status, 200);
  assert.equal((await call('POST', `/owner/employees/${gen.json.employee.id}/active`, { active: false }, ot)).status, 200); // keep the absent count below unchanged
  const list = await call('GET', '/owner/employees', undefined, ot);
  assert.equal(list.json.find((x: any) => x.externalId === 'E001').username, 'asha', 'owner list shows usernames');
  assert.equal((await call('GET', '/owner/dashboard', undefined, (await call('POST', '/auth/login', { identifier: 'asha', password: 'Pass1234' })).json.token)).status, 401, 'employee cannot use owner API');

  const l = await call('POST', '/auth/login', { identifier: 'asha', password: 'Pass1234' });
  assert.equal(l.status, 200); tok = l.json.token;
  const here = { lat: 12.9716, lng: 77.5946, accuracy: 10, isMock: false };

  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(1) }, tok)).json.code, 'FACE_NOT_REGISTERED');
  // registration needs the owner's approval
  assert.equal((await call('POST', '/me/face/reset-request', { reason: 'x' }, tok)).json.code, 'NOT_REGISTERED');
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(1), photo: 'AAAA' }, tok)).json.status, 'PENDING');
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(1) }, tok)).json.code, 'FACE_PENDING');
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(1) }, tok)).json.code, 'FACE_PENDING');
  const regs = await call('GET', '/owner/face-registrations', undefined, ot);
  assert.equal(regs.json.length, 1); assert.equal(regs.json[0].photo, 'AAAA');
  assert.equal((await call('GET', '/owner/face-registrations', undefined, tok)).status, 401);
  // owner rejects once -> employee sees the reason and can register again
  assert.equal((await call('POST', `/owner/face-registrations/${regs.json[0].id}/reject`, { note: 'too dark' }, ot)).status, 200);
  assert.equal((await call('GET', '/me', undefined, tok)).json.faceNote, 'too dark');
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(1), photo: 'BBBB' }, tok)).status, 200);
  assert.equal((await call('POST', `/owner/face-registrations/${regs.json[0].id}/approve`, {}, ot)).status, 200);
  assert.equal((await call('POST', `/owner/face-registrations/${regs.json[0].id}/approve`, {}, ot)).json.code, 'RESOLVED');
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(1) }, tok)).json.code, 'FACE_EXISTS');

  // ---- registration quality rules ----
  const imran = (await call('POST', '/auth/login', { identifier: 'imran', password: 'Pass1234' })).json.token;
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(5, 3) }, imran)).status, 400, 'needs at least 4 samples');
  assert.equal((await call('POST', '/me/face/register', { embeddings: [...reg(5, 3), ...reg(9, 3)] }, imran)).json.code, 'REGISTRATION_INCONSISTENT', 'mixed people');
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(emb(5).map(x => x * 2)) }, imran)).json.code, 'BAD_FACE_DATA', 'not a unit vector');
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg([1, 2, 3]) }, imran)).json.code, 'BAD_FACE_DATA', 'wrong length');
  const raviT = (await call('POST', '/auth/login', { identifier: 'ravi', password: 'Pass1234' })).json.token;
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(3) }, raviT)).status, 200);
  const raviRow = await prisma.employee.findUniqueOrThrow({ where: { externalId: 'E002' } });
  assert.equal((await call('POST', `/owner/face-registrations/${raviRow.id}/approve`, {}, ot)).status, 200);

  assert.equal((await punchCall({ type: 'IN', ...here, isMock: true, embedding: emb(1) }, tok)).json.code, 'MOCK_LOCATION');
  assert.equal((await punchCall({ type: 'IN', ...here, accuracy: 200, embedding: emb(1) }, tok)).json.code, 'GPS_ACCURACY');
  assert.equal((await punchCall({ type: 'IN', ...here, lat: 12.99, embedding: emb(1) }, tok)).json.code, 'OUTSIDE_GEOFENCE');
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(7) }, tok)).json.code, 'FACE_MISMATCH');
  assert.equal((await punchCall({ type: 'OUT', ...here, embedding: emb(1) }, tok)).json.code, 'NOT_IN');

  // ---- face check protections ----
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(1), actions: ['BLINK'] }, tok)).json.code, 'LIVENESS_FAILED', 'wrong challenge actions');
  assert.equal((await punchCall({ type: 'IN', ...here, frames: [[1, 2, 3], [1, 2, 3]] }, tok)).json.code, 'BAD_FACE_DATA');
  assert.equal((await punchCall({ type: 'IN', ...here, frames: [emb(1).map(x => x * 3), emb(1)] }, tok)).json.code, 'BAD_FACE_DATA', 'tampered vector');
  assert.equal((await punchCall({ type: 'IN', ...here, frames: [emb(1), emb(7)] }, tok)).json.code, 'FACE_INCONSISTENT', 'two different faces in one check');
  const ch = (await call('GET', '/me/punch-challenge?type=IN', undefined, tok)).json;
  const replay = { type: 'IN', ...here, nonce: ch.nonce, frames: [emb(7), emb(7)], actionsDone: ch.actions };
  assert.equal((await call('POST', '/punch', replay, tok)).json.code, 'FACE_MISMATCH');
  assert.equal((await call('POST', '/punch', replay, tok)).json.code, 'CHALLENGE_INVALID', 'a challenge works only once');
  assert.equal((await call('POST', '/punch', { ...replay, nonce: 'deadbeefdeadbeef' }, tok)).json.code, 'CHALLENGE_INVALID', 'unknown challenge');
  // someone else's face on my account is recognised as that person
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(3) }, tok)).json.code, 'FACE_OTHER_PERSON');
  const fa = await call('GET', '/owner/face-attempts?failedOnly=true', undefined, ot);
  assert.ok(fa.json.length >= 4 && fa.json.some((x: any) => x.reason.startsWith('LOOKS_LIKE_OTHER')), 'failed checks are logged');
  assert.equal((await call('GET', '/owner/face-attempts', undefined, tok)).status, 401);

  const pin1 = await punchCall({ type: 'IN', ...here, embedding: emb(1) }, tok);
  assert.equal(pin1.status, 200, JSON.stringify(pin1.json));
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(1) }, tok)).json.code, 'ALREADY_IN');
  // lunch break
  const P = (type: string, extra: any = {}) => punchCall({ type, ...here, embedding: emb(1), ...extra }, tok);
  assert.equal((await P('LUNCH_IN')).json.code, 'NO_LUNCH_OUT');
  assert.equal((await P('LUNCH_OUT')).json.code, 'LUNCH_WINDOW', 'outside the lunch window');
  await call('PUT', '/owner/settings', { lunchStart: '00:01', lunchEnd: '23:58' }, ot);
  assert.equal((await P('LUNCH_OUT')).status, 200);
  assert.equal((await P('LUNCH_OUT')).json.code, 'LUNCH_ALREADY');
  const li = await P('LUNCH_IN'); assert.equal(li.status, 200); assert.ok(li.json.attendance.lunchIn);
  assert.equal((await P('LUNCH_IN')).json.code, 'LUNCH_DONE');
  const out = await P('OUT');
  assert.equal(out.status, 200); assert.ok(out.json.attendance.earlyMinutes > 0, 'early exit flagged');
  assert.equal((await P('LUNCH_OUT')).json.code, 'ALREADY_OUT');

  // face reset flow
  assert.equal((await call('POST', '/me/face/reset-request', { reason: 'beard' }, tok)).status, 200);
  const reqs = await call('GET', '/owner/face-requests', undefined, ot);
  assert.equal(reqs.json.length, 1);
  await call('POST', `/owner/face-requests/${reqs.json[0].id}/approve`, {}, ot);
  assert.equal((await call('GET', '/me', undefined, tok)).json.faceStatus, 'NONE');

  // after approval of a reset, a new registration goes back to PENDING
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(1) }, tok)).json.status, 'PENDING');

  // ---- leave ----
  const day = (n: number) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
  const ravi = (await call('POST', '/auth/login', { identifier: 'ravi', password: 'Pass1234' })).json.token;
  const L = (b: any, t = ravi) => call('POST', '/me/leaves', b, t);
  assert.equal((await L({ fromDate: day(5), toDate: day(4), reason: 'trip' })).status, 400, 'end before start');
  assert.equal((await L({ fromDate: day(3), toDate: day(4), reason: 'a' })).status, 400, 'reason required');
  assert.equal((await L({ fromDate: day(-30), toDate: day(-29), reason: 'old' })).status, 400, 'too far in the past');
  const lv = await L({ fromDate: day(3), toDate: day(4), reason: 'family function', type: 'CASUAL' });
  assert.equal(lv.status, 200);
  assert.equal((await L({ fromDate: day(4), toDate: day(5), reason: 'again' })).json.code, 'LEAVE_OVERLAP');
  assert.equal((await call('GET', '/owner/leaves', undefined, ot)).json.length, 1);
  assert.equal((await call('POST', `/owner/leaves/${lv.json.id}/reject`, {}, ot)).status, 400, 'reject needs a reason');
  assert.equal((await call('POST', `/owner/leaves/${lv.json.id}/approve`, { note: 'ok' }, ot)).status, 200);
  assert.equal((await call('POST', `/owner/leaves/${lv.json.id}/approve`, {}, ot)).json.code, 'RESOLVED');
  assert.equal((await call('POST', `/me/leaves/${lv.json.id}/cancel`, {}, ravi)).status, 200, 'future approved leave can be cancelled');
  assert.equal((await L({ fromDate: day(3), toDate: day(4), reason: 'family function' })).status, 200, 'dates free again after cancel');
  const asha = tok;
  assert.equal((await call('GET', '/me/leaves', undefined, ravi)).json.length, 2);
  assert.equal((await L({ fromDate: day(0), toDate: day(0), reason: 'already here' }, asha)).json.code, 'ALREADY_WORKED');
  assert.equal((await call('POST', `/me/leaves/${lv.json.id}/cancel`, {}, asha)).status, 404, "cannot touch someone else's leave");

  // leave covering a future day -> nightly job writes LEAVE instead of ABSENT
  const { markAbsentees } = await import('./punch');
  const lv2 = (await call('GET', '/owner/leaves', undefined, ot)).json[0];
  await call('POST', `/owner/leaves/${lv2.id}/approve`, {}, ot);
  await markAbsentees(day(3));
  const raviEmp = await prisma.employee.findUniqueOrThrow({ where: { externalId: 'E002' } });
  assert.equal((await prisma.attendance.findUniqueOrThrow({ where: { employeeId_date: { employeeId: raviEmp.id, date: day(3) } } })).status, 'LEAVE');
  // revoke: the not-yet-happened LEAVE row disappears
  await call('POST', `/owner/leaves/${lv2.id}/revoke`, { note: 'needed at work' }, ot);
  assert.equal(await prisma.attendance.count({ where: { employeeId: raviEmp.id, date: day(3) } }), 0, 'revoke removes the not-yet-happened LEAVE row');
  // a person on leave today cannot punch
  const meena = (await call('POST', '/auth/login', { identifier: 'meena', password: 'Pass1234' })).json.token;
  await call('POST', '/me/face/register', { embeddings: reg(2) }, meena);
  const meenaEmp = await prisma.employee.findUniqueOrThrow({ where: { externalId: 'E003' } });
  await call('POST', `/owner/face-registrations/${meenaEmp.id}/approve`, {}, ot);
  const todayStr = (await call('GET', '/me/today', undefined, meena)).json.date;
  const ml = await L({ fromDate: todayStr, toDate: todayStr, reason: 'unwell', type: 'SICK' }, meena);
  assert.equal(ml.status, 200);
  await call('POST', `/owner/leaves/${ml.json.id}/approve`, {}, ot);
  assert.equal((await call('GET', '/me/today', undefined, meena)).json.onLeave, true);
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(2) }, meena)).json.code, 'ON_LEAVE');
  assert.equal((await prisma.attendance.findUniqueOrThrow({ where: { employeeId_date: { employeeId: meenaEmp.id, date: todayStr } } })).status, 'LEAVE', 'approved leave for today shows as LEAVE');

  // ---- leave quota + half day ----
  const divya = (await call('POST', '/auth/login', { identifier: 'divya', password: 'Pass1234' })).json.token;
  const D = (b: any, t = divya) => call('POST', '/me/leaves', b, t);
  const bal = async () => (await call('GET', '/me/leave-balance', undefined, divya)).json;
  assert.equal((await bal()).quotaEnabled, false, 'quota is off by default');
  assert.equal((await bal()).balances[0].available, null, 'unlimited without quota');
  assert.equal((await call('PUT', '/owner/settings', { leaveQuotaEnabled: true, leaveQuotaCasual: 2, leaveQuotaSick: 1, leaveQuotaOther: 0, leaveYearStartMonth: 1 }, ot)).status, 200);
  assert.equal((await bal()).balances[0].available, 2);
  const c2 = await D({ fromDate: day(10), toDate: day(11), reason: 'wedding', type: 'CASUAL' });
  assert.equal(c2.status, 200); assert.equal(c2.json.days, 2);
  assert.equal((await bal()).balances[0].available, 0, 'pending leave is reserved');
  assert.equal((await D({ fromDate: day(15), toDate: day(15), reason: 'one more', type: 'CASUAL' })).json.code, 'QUOTA_EXCEEDED');
  assert.equal((await D({ fromDate: day(16), toDate: day(16), reason: 'other', type: 'OTHER' })).json.code, 'QUOTA_EXCEEDED', 'quota 0 = not allowed');
  assert.equal((await D({ fromDate: day(16), toDate: day(17), reason: 'half', type: 'SICK', halfDay: true, halfSession: 'FIRST' })).status, 400, 'half day must be one day');
  assert.equal((await D({ fromDate: day(16), toDate: day(16), reason: 'half', type: 'SICK', halfDay: true })).status, 400, 'half day needs a session');
  const sh = await D({ fromDate: day(16), toDate: day(16), reason: 'dentist', type: 'SICK', halfDay: true, halfSession: 'SECOND' });
  assert.equal(sh.status, 200); assert.equal(sh.json.days, 0.5);
  assert.equal((await bal()).balances[1].available, 0.5, 'half a sick day left');
  assert.equal((await D({ fromDate: day(16), toDate: day(16), reason: 'again', type: 'SICK', halfDay: true, halfSession: 'FIRST' })).json.code, 'LEAVE_OVERLAP');
  const pend = (await call('GET', '/owner/leaves', undefined, ot)).json.find((x: any) => x.id === c2.json.id);
  assert.equal(pend.balance.quota, 2); assert.equal(pend.balance.available, 2, 'owner sees what was left before this request');
  await call('POST', `/owner/leaves/${c2.json.id}/approve`, {}, ot);
  assert.equal((await bal()).balances[0].used, 2, 'approved leave counts as used');
  assert.equal((await call('POST', `/me/leaves/${c2.json.id}/cancel`, {}, divya)).status, 200);
  assert.equal((await bal()).balances[0].available, 2, 'cancel gives the days back');
  await call('PUT', '/owner/settings', { holidays: day(9) }, ot);
  assert.equal((await D({ fromDate: day(8), toDate: day(10), reason: 'holiday inside', type: 'CASUAL' })).json.days, 2, 'holiday on day(9) is not counted');
  await call('PUT', '/owner/settings', { leaveQuotaEnabled: false }, ot);
  assert.equal((await D({ fromDate: day(20), toDate: day(22), reason: 'long break', type: 'OTHER' })).status, 200, 'no quota = unlimited');

  // half-day punch: morning off -> expected from lunch end, so arriving "now" is late
  await call('PUT', '/owner/settings', { lunchStart: '00:01', lunchEnd: '00:02' }, ot);
  const raviEmp2 = await prisma.employee.findUniqueOrThrow({ where: { externalId: 'E002' } });
  await call('POST', '/me/face/register', { embeddings: reg(3) }, ravi);
  await call('POST', `/owner/face-registrations/${raviEmp2.id}/approve`, {}, ot);
  const hl = await L({ fromDate: todayStr, toDate: todayStr, reason: 'morning appointment', halfDay: true, halfSession: 'FIRST' });
  assert.equal(hl.status, 200);
  await call('POST', `/owner/leaves/${hl.json.id}/approve`, {}, ot);
  const ts = (await call('GET', '/me/today', undefined, ravi)).json;
  assert.equal(ts.onLeave, false); assert.equal(ts.halfLeave, 'FIRST');
  const hp = await punchCall({ type: 'IN', ...here, embedding: emb(3) }, ravi);
  assert.equal(hp.status, 200, JSON.stringify(hp.json)); assert.equal(hp.json.attendance.halfLeave, 'FIRST');
  assert.equal(hp.json.attendance.status, 'LATE', 'half-day (morning off) is measured from lunch end');
  assert.equal(await prisma.attendance.count({ where: { employeeId: raviEmp2.id, date: todayStr, status: 'LEAVE' } }), 0, 'half day never makes a LEAVE row');

  // slow appearance change: a confident-but-different look is remembered (7 templates), a near-identical one is not
  assert.equal(JSON.parse((await prisma.employee.findUniqueOrThrow({ where: { id: raviEmp2.id } })).faceData).length, 6);
  const newLook = mix(emb(3), emb(9), 0.6); // ~0.86 similar to the enrolled face
  assert.equal((await punchCall({ type: 'OUT', ...here, embedding: newLook }, ravi)).status, 200);
  assert.equal(JSON.parse((await prisma.employee.findUniqueOrThrow({ where: { id: raviEmp2.id } })).faceData).length, 7, 'new look stored');

  // ---- look-alikes: two employees whose faces are almost identical ----
  const sneha = (await call('POST', '/auth/login', { identifier: 'sneha', password: 'Pass1234' })).json.token;
  const arjun = (await call('POST', '/auth/login', { identifier: 'arjun', password: 'Pass1234' })).json.token;
  await call('POST', '/me/face/register', { embeddings: reg(11) }, sneha);
  const snehaRow = await prisma.employee.findUniqueOrThrow({ where: { externalId: 'E007' } });
  await call('POST', `/owner/face-registrations/${snehaRow.id}/approve`, {}, ot);
  const twin = mix(emb(11), emb(13), 0.2);
  assert.equal((await call('POST', '/me/face/register', { embeddings: reg(twin) }, arjun)).status, 200);
  const regs2 = await call('GET', '/owner/face-registrations', undefined, ot);
  const arjunReg = regs2.json.find((x: any) => x.externalId === 'E008');
  assert.equal(arjunReg.similarTo, 'Sneha Reddy', 'owner is warned about a look-alike'); assert.ok(arjunReg.similarScore > 0.9);
  await call('POST', `/owner/face-registrations/${arjunReg.id}/approve`, {}, ot);
  assert.equal((await punchCall({ type: 'IN', ...here, embedding: emb(11) }, sneha)).json.code, 'FACE_AMBIGUOUS', 'too close to call -> refuse');
  assert.equal((await call('PUT', '/owner/settings', { faceThreshold: 0.2 }, ot)).status, 400, 'threshold sanity');
  // settings validation
  assert.equal((await call('PUT', '/owner/settings', { lunchStart: '15:00', lunchEnd: '14:00' }, ot)).status, 400);
  assert.equal((await call('PUT', '/owner/settings', { holidays: 'tomorrow' }, ot)).status, 400);
  assert.equal((await call('PUT', '/owner/settings', { holidays: day(9) }, ot)).status, 200);
  assert.equal(await markAbsentees(day(9)), 0, 'holiday: nobody marked absent');

  // absent marking for today: everyone without a record (asha + ravi punched, meena on leave) -> 9
  assert.equal(await markAbsentees(), 9);

  // ---- optional company ERP: only for unknown usernames, only when an address is configured ----
  const http = await import('node:http');
  const erp = http.createServer((rq, rs) => {
    let b = ''; rq.on('data', d => (b += d));
    rq.on('end', () => {
      if (JSON.parse(b || '{}').password === 'erp-pass') { rs.setHeader('content-type', 'application/json'); rs.end(JSON.stringify({ user: { id: 'X9', name: 'Zed Erp', role: 'employee', department: 'Ops', active: true } })); }
      else { rs.statusCode = 401; rs.end('{}'); }
    });
  }).listen(0);
  const erpUrl = `http://localhost:${(erp.address() as any).port}/login`;
  assert.equal((await call('POST', '/auth/login', { identifier: 'zed', password: 'erp-pass' })).json.code, 'BAD_CREDENTIALS', 'no ERP configured: unknown user refused');
  assert.equal((await call('PUT', '/owner/settings', { erpLoginUrl: erpUrl, erpUserPath: 'user', erpOwnerRoles: 'admin' }, ot)).status, 200);
  const zed = await call('POST', '/auth/login', { identifier: 'zed', password: 'erp-pass' });
  assert.equal(zed.status, 200); assert.equal(zed.json.name, 'Zed Erp');
  assert.equal((await call('POST', '/auth/login', { identifier: 'zed', password: 'nope' })).json.code, 'BAD_CREDENTIALS');
  assert.equal((await call('POST', '/auth/login', { identifier: 'asha', password: 'wrong' })).json.code, 'BAD_CREDENTIALS', 'local users never fall through to the ERP');
  erp.close(); await call('PUT', '/owner/settings', { erpLoginUrl: '' }, ot);

  const csv = await call('GET', `/owner/report/export.csv?month=${new Date().toISOString().slice(0, 7)}`, undefined, ot);
  assert.equal(csv.status, 200);
  // ---- production start: never crashes, never leaves owner/owner123 open ----
  const { ensureOwner: boot2 } = await import('./bootstrap');
  const oldEnv = process.env.NODE_ENV, oldPw = process.env.OWNER_PASSWORD;
  process.env.NODE_ENV = 'production'; delete process.env.OWNER_PASSWORD;
  await boot2(); // no OWNER_PASSWORD: must still start
  assert.equal((await call('POST', '/auth/login', { identifier: 'owner', password: 'owner123' })).json.code, 'OWNER_LOCKED', 'default owner password is refused in production');
  process.env.OWNER_PASSWORD = 'a-much-stronger-pw-1';
  await boot2(); // strong password given: stored password is updated and login re-enabled
  assert.equal((await call('POST', '/auth/login', { identifier: 'owner', password: 'a-much-stronger-pw-1' })).status, 200, 'owner can log in with OWNER_PASSWORD');
  assert.equal((await call('POST', '/auth/login', { identifier: 'owner', password: 'owner123' })).status, 401, 'old default no longer works');
  process.env.NODE_ENV = oldEnv; if (oldPw === undefined) delete process.env.OWNER_PASSWORD; else process.env.OWNER_PASSWORD = oldPw;
  console.log('ALL SMOKE TESTS PASSED'); srv.close(); await prisma.$disconnect(); await mongo.stop();
})().catch(e => { console.error(e); process.exit(1); });
