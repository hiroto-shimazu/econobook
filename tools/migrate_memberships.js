/*
Run this script locally to migrate `memberships` documents to deterministic IDs
of the form `${communityId}_${userId}`.

Requirements:
  - Node.js installed
  - npm install firebase-admin
  - Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON with access to the
    Firestore database, or run this from an authenticated environment.

Usage:
  # dry-run (no writes)
  node migrate_memberships.js --dryRun

  # perform migration (creates new docs; does NOT delete old docs by default)
  node migrate_memberships.js

  # perform migration and delete old docs when moved
  node migrate_memberships.js --deleteOld

Notes:
  - The script will only move docs that have clear community id and user id fields
    (fields: 'cid' or 'communityId', and 'uid' or 'userId').
  - New doc will be written with the same fields. If the target id already exists,
    it will be skipped unless --overwrite is provided.
*/

const admin = require('firebase-admin');
const { argv } = require('process');

const dryRun = argv.includes('--dryRun');
const deleteOld = argv.includes('--deleteOld');
const overwrite = argv.includes('--overwrite');

if (!admin.apps.length) {
  try {
    admin.initializeApp();
  } catch (e) {
    console.error('Failed to initialize firebase-admin. Make sure GOOGLE_APPLICATION_CREDENTIALS is set.');
    console.error(e);
    process.exit(1);
  }
}

const db = admin.firestore();

async function main() {
  console.log('Starting memberships migration');
  console.log('dryRun=', dryRun, 'deleteOld=', deleteOld, 'overwrite=', overwrite);

  const snapshot = await db.collection('memberships').get();
  console.log('Found', snapshot.size, 'membership docs');

  let moved = 0;
  let skipped = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const cid = data.cid || data.communityId || data.community_id || null;
    const uid = data.uid || data.userId || data.user_id || null;
    if (!cid || !uid) {
      console.warn(`Skipping doc ${doc.id}: missing cid or uid`);
      skipped++;
      continue;
    }
    const targetId = `${cid}_${uid}`;
    if (doc.id === targetId) {
      // already deterministic
      continue;
    }
    const targetRef = db.collection('memberships').doc(targetId);
    const targetSnap = await targetRef.get();
    if (targetSnap.exists && !overwrite) {
      console.warn(`Target ${targetId} already exists. Skipping ${doc.id}`);
      skipped++;
      continue;
    }

    console.log(`Migrating ${doc.id} -> ${targetId}`);
    if (dryRun) {
      moved++;
      continue;
    }

    // write new doc
    await targetRef.set(data, { merge: false });
    moved++;
    if (deleteOld) {
      await doc.ref.delete();
    }
  }

  console.log('Done. moved=', moved, 'skipped=', skipped);
}

main().catch((e) => {
  console.error('Migration failed', e);
  process.exit(1);
});
