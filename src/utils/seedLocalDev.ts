// One-off script for local development: creates a User, Workspace, and
// Membership, then generates an API key you can use to call /verify-* routes.
// This repo has no public signup route (that lives in a separate dashboard
// app), so on a fresh database there is no other way to get a usable key.
//
// Run with: pnpm ts-node src/utils/seedLocalDev.ts
import { prisma } from './prisma';
import { generateApiKey } from '../middleware/apiKeyAuth';

async function main() {
    const user = await prisma.user.create({
        data: {
            email: 'dev@example.com',
            name: 'Local Dev',
        },
    });

    const workspace = await prisma.workspace.create({
        data: {
            name: 'Local Dev Workspace',
        },
    });

    await prisma.membership.create({
        data: {
            userId: user.id,
            workspaceId: workspace.id,
            role: 'OWNER',
        },
    });

    const { rawKey } = await generateApiKey(user.id);

    console.log('\nSeed complete.');
    console.log('User ID:', user.id);
    console.log('Workspace ID:', workspace.id);
    console.log('\nYour API key (copy it now, it is not stored anywhere retrievable):');
    console.log(rawKey);
    console.log('\nUse it as a header on requests, e.g.:');
    console.log(`curl -X POST http://localhost:3001/verify-cbe -H "x-api-key: ${rawKey}" -H "Content-Type: application/json" -d "{\\"reference\\":\\"...\\",\\"accountSuffix\\":\\"...\\"}"`);
}

main()
    .catch((err) => {
        console.error('Seed failed:', err);
        process.exitCode = 1;
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
