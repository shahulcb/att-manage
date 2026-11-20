import './env';
import express from 'express';
import cors from 'cors';
import cron from 'node-cron';
import { router } from './routes';
import { errorHandler } from './util';
import { ensureOwner } from './bootstrap';
import { getSettings, prisma } from './db';
import { markAbsentees } from './punch';

export const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.get('/health', (_q, r) => { r.json({ ok: true }); });
app.use('/api', router);
app.use(errorHandler);

if (require.main === module) {
  const port = Number(process.env.PORT || 4000);
  process.on('unhandledRejection', e => console.error('unhandled rejection (kept running):', (e as Error)?.message ?? e));
  // Atlas / DNS can blip at startup: retry instead of crashing
  const boot = async () => {
    for (let i = 1; ; i++) {
      try { await ensureOwner(); return; }
      catch (e: any) { if (/must be set/.test(String(e.message))) throw e; /* bad configuration: fail fast, do not retry */ console.error(`database not reachable (attempt ${i}):`, String(e.message).split('\n').pop()); if (i >= 20) throw e; await new Promise(r => setTimeout(r, 3000)); }
    }
  };
  boot().then(async () => {
    app.listen(port, '0.0.0.0', () => console.log(`API on :${port}`));
    // mark absentees every night at 23:55 for working days (uses org timezone date)
    // keep the face-check log for 90 days
    cron.schedule('58 23 * * *', async () => { const n = await prisma.faceAttempt.deleteMany({ where: { createdAt: { lt: new Date(Date.now() - 90 * 86400000) } } }); console.log('old face attempts removed', n.count); });
    cron.schedule('55 23 * * *', async () => { const s = await getSettings(); console.log('absent marked', await markAbsentees(), s.timezone); });
  });
}
