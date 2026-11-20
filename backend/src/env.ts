import fs from 'fs';
if (fs.existsSync('.env')) process.loadEnvFile('.env');
