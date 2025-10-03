#!/usr/bin/env node
// tools/cleanup_orphan_members.js
// Usage:
//  node cleanup_orphan_members.js --serviceAccount=/path/to/serviceAccountKey.json [--communityId=COMMUNITY_ID] [--dryRun]
//
// This script uses the Firebase Admin SDK to list all Auth users and then
// scans the Firestore `memberships` collection for entries whose `uid` is not
// present in Auth. It will delete those membership documents unless --dryRun
// is specified.

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  args.forEach(a => {
    if (a.startsWith('--serviceAccount=')) out.serviceAccount = a.split('=')[1];
    if (a.startsWith('--communityId=')) out.communityId = a.split('=')[1];
    if (a === '--dryRun') out.dryRun = true;
  });
  return out;
}

async function listAllAuthUids() {
  const uids = new Set();
  let nextPageToken;
  do {
    const res = await admin.auth().listUsers(1000, nextPageToken);
    res.users.forEach(u => uids.add(u.uid));
    nextPageToken = res.pageToken;
  } while (nextPageToken);
  return uids;
}

async function run() {
  const opts = parseArgs();
  if (!opts.serviceAccount && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error('Provide --serviceAccount=path or set GOOGLE_APPLICATION_CREDENTIALS env var');
    process.exit(2);
  }

  const serviceAccountPath = opts.serviceAccount || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (opts.serviceAccount && !fs.existsSync(serviceAccountPath)) {
    console.error('serviceAccount file not found:', serviceAccountPath);
    process.exit(2);
  }

  const sa = require(path.resolve(serviceAccountPath));
  admin.initializeApp({
    credential: admin.credential.cert(sa),
  });

  const firestore = admin.firestore();
  console.log('Fetching auth users...');
  const uids = await listAllAuthUids();
  console.log('Auth users count:', uids.size);

  // Build query
  let membershipsRef = firestore.collection('memberships');
  if (opts.communityId) {
    console.log('Filtering by communityId =', opts.communityId);
    membershipsRef = membershipsRef.where('cid', '==', opts.communityId);
  }

  console.log('Fetching memberships...');
  const snapshot = await membershipsRef.get();
  console.log('Membership docs found:', snapshot.size);

  let scanned = 0;
  let deleted = 0;
  const orphans = [];
  for (const doc of snapshot.docs) {
    scanned++;
    const data = doc.data();
    const uid = data.uid || data.userId || null;
    if (!uid) {
      // consider as orphan
      orphans.push({id: doc.id, uid: null});
      continue;
    }
    if (!uids.has(uid)) {
      orphans.push({id: doc.id, uid});
    }
  }

  console.log('Orphans detected:', orphans.length);
  if (orphans.length > 0) {
    orphans.forEach(o => console.log(' -', o.id, o.uid));
    if (opts.dryRun) {
      console.log('Dry run, exiting without deletions.');
    } else {
      console.log('Deleting orphan memberships...');
      for (const o of orphans) {
        await firestore.collection('memberships').doc(o.id).delete();
        deleted++;
      }
      console.log('Deleted:', deleted);
    }
  }

  console.log('Done. scanned=', scanned, ' deleted=', deleted);
  process.exit(0);
}

run().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
