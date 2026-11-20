import { randomBytes } from 'node:crypto';
import { HttpError } from './util';

// Single-use liveness challenges: stops a recorded request being replayed and makes the required actions unpredictable.
// (In-memory: fine for one server instance. Use Redis/Mongo if you scale out.)
type C = { employeeId: string; type: string; actions: string[]; exp: number };
const store = new Map<string, C>();
const ACTIONS = ['BLINK', 'TURN', 'SMILE'];

export function issueChallenge(employeeId: string, type: string) {
  const now = Date.now();
  for (const [k, v] of store) if (v.exp < now) store.delete(k);
  const shuffled = [...ACTIONS].sort(() => Math.random() - 0.5);
  const c = { employeeId, type, actions: shuffled.slice(0, 2), exp: now + 120_000 };
  const nonce = randomBytes(16).toString('hex');
  store.set(nonce, c);
  return { nonce, actions: c.actions };
}

export function consumeChallenge(nonce: string, employeeId: string, type: string) {
  const c = store.get(nonce);
  store.delete(nonce); // single use, even when it fails
  if (!c || c.exp < Date.now() || c.employeeId !== employeeId || c.type !== type)
    throw new HttpError(409, 'CHALLENGE_INVALID', 'The face check expired. Please try again.');
  return c.actions;
}
