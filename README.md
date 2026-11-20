# Attendance (Face + Location Punch)

- `backend/` – Node + Express + TypeScript + Prisma (SQLite for dev, switch provider to PostgreSQL for production)
- `mobile/`  – Flutter Android app (employee + owner), on-device face recognition (ML Kit + MobileFaceNet TFLite)

## Run the backend
```bash
cd backend
cp .env.example .env        # set JWT_SECRET, OWNER_PASSWORD
npm install
npx prisma db push
npm run seed                # creates owner, demo staff and attendance, and points login at the built-in MOCK ERP
npm run dev                 # http://localhost:4000
npm test                    # end-to-end smoke tests (wipes the dev DB! re-run `npm run seed` after)
```
Owner login: `owner` / `owner123` (change in `.env` before first run). Seeded mock ERP logins: owner `boss` / `admin123`; employees `asha`, `ravi`, `meena`, ... / `pass123`.

## Run the app
```bash
cd mobile
flutter run                 # emulator: server defaults to http://10.0.2.2:4000/api
```
On a real phone, tap the plug icon on the login screen and enter `http://<your-computer-LAN-IP>:4000/api`.
Use HTTPS in production (cleartext is enabled only for development).

## Connecting the real ERP
Only the **login** is connected to the ERP. Users sign in with their ERP username and password; an employee record is created on first login (name and department come from the ERP login response). The ERP login settings (URL, field names, user path, owner roles, mapping) live in the database, not in the app. There is no employee-list sync.

## Rules implemented
- One office location + radius (default 100 m, adjustable); GPS verified on the server too
- Mock GPS blocked; weak GPS (> max error) asks to retry
- Face: on-device match + liveness (blink), server re-verifies the embedding; face change -> request owner reset
- Late = punch in after start + grace; Early exit = punch out before end; no punch in on a working day = ABSENT (nightly 23:55 job)
- Punch out is never auto-closed; missing punch-outs show in reports
- Offline punches are queued on the phone and synced later (idempotent, rejects shown to the user)
- Owner can add/correct attendance (reason required, audit logged); CSV export per month
