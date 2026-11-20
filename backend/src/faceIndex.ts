import { prisma } from './db';
import { cosine } from './util';

type Entry = { name: string; templates: number[][] };
let cache: Map<string, Entry> | null = null;
let loadedAt = 0;

export const invalidateFaces = () => { cache = null; };

async function load() {
  if (cache && Date.now() - loadedAt < 5 * 60_000) return cache;
  const rows = await prisma.employee.findMany({ where: { faceStatus: 'REGISTERED', active: true }, select: { id: true, name: true, faceData: true } });
  cache = new Map(rows.map(r => [r.id, { name: r.name, templates: JSON.parse(r.faceData) as number[][] }]));
  loadedAt = Date.now();
  return cache;
}

export const bestScore = (templates: number[][], probe: number[]) => templates.reduce((m, t) => Math.max(m, cosine(t, probe)), -1);

/** A real MobileFaceNet embedding: 192 finite numbers with length ~1. Rejects garbage and tampered vectors. */
export function validEmbedding(e: unknown): e is number[] {
  if (!Array.isArray(e) || e.length !== 192 || !e.every(x => typeof x === 'number' && Number.isFinite(x))) return false;
  const norm = Math.sqrt(e.reduce((a, x) => a + x * x, 0));
  return Math.abs(norm - 1) < 0.05;
}

/** Best match of the probes against every OTHER registered employee (1:N identification). */
export async function bestOther(excludeId: string, probes: number[][]) {
  const idx = await load();
  let best = { score: -1, id: '', name: '' };
  for (const [id, e] of idx) {
    if (id === excludeId) continue;
    for (const p of probes) {
      const sc = bestScore(e.templates, p);
      if (sc > best.score) best = { score: sc, id, name: e.name };
    }
  }
  return best;
}

export async function updateCachedTemplates(id: string, templates: number[][]) {
  const idx = await load();
  const e = idx.get(id);
  if (e) e.templates = templates;
}
