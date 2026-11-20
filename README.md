# Attendance (Face + Location Punch)

- `backend/` – Node + Express + TypeScript + Prisma (SQLite for dev, switch provider to PostgreSQL for production)
- `mobile/`  – Flutter Android app (employee + owner), on-device face recognition (ML Kit + MobileFaceNet TFLite)

## Run the backend
```bash
cd backend
cp .env.example .env        # set JWT_SECRET, OWNER_PASSWORD
npm install
npx prisma db push
npm run seed                # creates demo employees, their accounts and sample attendance (never overwrites existing settings)
npm run dev                 # http://localhost:4000
npm test                    # end-to-end smoke tests (wipes the dev DB! re-run `npm run seed` after)
```
Accounts are stored in the database (`User` collection, bcrypt hashes). `npm run seed` creates the owner (`owner`) and 12 demo employees
(`asha`, `ravi`, `meena`, ...) and prints the generated password once. Set your own with `SEED_PASSWORD=...` (employees) and `SEED_OWNER_PASSWORD=...`.
Nothing is hardcoded. The owner adds real employees in the app (Employees tab, + button).

## Run the app
```bash
cd mobile
flutter run                 # emulator: server defaults to http://10.0.2.2:4000/api
```
The server address is fixed when the app is built: `flutter run --dart-define=API_BASE=http://<your-computer-LAN-IP>:4000/api` (over USB: `adb reverse tcp:4000 tcp:4000` and `http://localhost:4000/api`).
Use HTTPS in production (cleartext is enabled only for development).

## Accounts and the (optional) company ERP
Sign-in uses the `User` collection in MongoDB (username + bcrypt hash). The owner creates employees in the app (Employees tab, + button), can reset a password (a generated one is shown once) and can deactivate an account.
A company ERP login can optionally be added later by setting `erpLoginUrl` (and its field mapping) in the database `Settings` document. It is only asked for usernames that do not exist locally, and it is off while `erpLoginUrl` is empty.

## Rules implemented
- One office location + radius (default 100 m, adjustable); GPS verified on the server too
- Mock GPS blocked; weak GPS (> max error) asks to retry
- Face: on-device match + liveness (blink), server re-verifies the embedding; face change -> request owner reset
- Late = punch in after start + grace; Early exit = punch out before end; no punch in on a working day = ABSENT (nightly 23:55 job)
- Punch out is never auto-closed; missing punch-outs show in reports
- Offline punches are queued on the phone and synced later (idempotent, rejects shown to the user)
- Owner can add/correct attendance (reason required, audit logged); CSV export per month
