const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');
const { GoogleGenAI } = require('@google/genai');

admin.initializeApp();
const db = admin.firestore();

const GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'healthyfast-f1f5a';
const VERTEX_LOCATION = 'us-central1';

/**
 * Cloud AI fallback for phones that can't run Gemini Nano on-device (see
 * lib/services/cloud_ai_service.dart). Only ever called after the user
 * has explicitly consented in-app (lib/widgets/cloud_ai_consent_sheet.dart)
 * — this function does no consent checking itself, that's a client-side
 * gate before the call is ever made.
 *
 * Calls Gemini via VERTEX AI, not the Gemini Developer API / AI Studio key.
 * No API key at all: authenticates as this function's own Cloud Functions
 * service account (Application Default Credentials), which Google Cloud
 * provides automatically at runtime. This sidesteps a live Google-side bug
 * where new "auth"-type AI Studio keys (the "AQ." prefix) are rejected with
 * 401 ACCESS_TOKEN_TYPE_UNSUPPORTED on both generateContent and the
 * Interactions API — see https://discuss.ai.google.dev (search
 * "AQ. ACCESS_TOKEN_TYPE_UNSUPPORTED") for other reports.
 *
 * SETUP BEFORE THIS WORKS (one-time, from the project root):
 *   1. Enable the Vertex AI API on the project:
 *        gcloud services enable aiplatform.googleapis.com --project=healthyfast-f1f5a
 *      (or: Google Cloud Console → APIs & Services → Enable "Vertex AI API")
 *   2. Grant this function's service account the Vertex AI User role:
 *        gcloud projects add-iam-policy-binding healthyfast-f1f5a \
 *          --member="serviceAccount:healthyfast-f1f5a@appspot.gserviceaccount.com" \
 *          --role="roles/aiplatform.user"
 *   3. Deploy: firebase deploy --only functions
 *
 * Note: Vertex AI has no free tier (unlike the AI Studio Gemini API), but
 * per-request cost for these short prompts is a fraction of a cent —
 * negligible at indie-app scale. It also does NOT use your data to train
 * Google's models (Vertex AI's data-use terms differ from the AI Studio
 * free tier) — if this stays the permanent setup, the in-app consent copy
 * should be updated to drop the "Google may use this to improve their
 * models" line, since it's no longer accurate.
 */
const genAI = new GoogleGenAI({
  vertexai: true,
  project: GCLOUD_PROJECT,
  location: VERTEX_LOCATION,
});

// Anti-abuse: every caller must be Firebase-authenticated (anonymous auth
// is fine — see FirebaseAuthGuard.ensureSignedIn in
// lib/services/cloud_ai_service.dart) so usage can be capped per-user, not
// just per-app. Without this, anyone who extracted the callable function
// name could script unlimited calls against our Vertex AI billing.
//
// Caps are read from Firestore (ai_config/limits) on every call so they
// can be tuned from the Firebase console without a redeploy. Defaults
// below apply if that doc doesn't exist yet.
const DEFAULT_PER_USER_DAILY_CAP = 30;
const DEFAULT_GLOBAL_DAILY_CAP = 3000;

async function enforceUsageCap(uid, kind) {
  const today = new Date().toISOString().slice(0, 10); // UTC YYYY-MM-DD

  let perUserCap = DEFAULT_PER_USER_DAILY_CAP;
  let globalCap = DEFAULT_GLOBAL_DAILY_CAP;
  try {
    const cfg = (await db.collection('ai_config').doc('limits').get()).data();
    if (cfg) {
      if (typeof cfg.perUserDailyCap === 'number') perUserCap = cfg.perUserDailyCap;
      if (typeof cfg.globalDailyCap === 'number') globalCap = cfg.globalDailyCap;
    }
  } catch (e) {
    console.error('[generateAiText] could not read ai_config/limits, using defaults:', e);
  }

  const userRef = db.collection('ai_usage').doc(`${uid}_${today}`);
  const globalRef = db.collection('ai_usage_global').doc(today);

  // Returns null when the call is allowed (and the counters have already
  // been incremented), or details of which cap was hit. A thrown error
  // inside runTransaction rolls back every write queued alongside it —
  // including a quota_hits report doc — so that record has to be written
  // *after* the transaction settles, not from inside it.
  const exceeded = await db.runTransaction(async (tx) => {
    const [userSnap, globalSnap] = await Promise.all([tx.get(userRef), tx.get(globalRef)]);
    const userCount = userSnap.exists ? (userSnap.data().count || 0) : 0;
    const globalCount = globalSnap.exists ? (globalSnap.data().count || 0) : 0;

    if (userCount >= perUserCap) return { type: 'user', count: userCount, cap: perUserCap };
    if (globalCount >= globalCap) return { type: 'global', count: globalCount, cap: globalCap };

    tx.set(userRef, { count: userCount + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    tx.set(globalRef, { count: globalCount + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return null;
  });

  if (exceeded) {
    // Greppable in `firebase functions:log` / Cloud Logging for a quick
    // check, and mirrored into Firestore below for a standing report —
    // see the `quota_hits` collection in the Firebase console.
    console.warn(`[QuotaExceeded] type=${exceeded.type} uid=${uid} kind=${kind} count=${exceeded.count} cap=${exceeded.cap} date=${today}`);
    try {
      // One doc per user per day (merge), so repeated blocked taps on the
      // same day don't spam the collection — `kind` just reflects the most
      // recent thing they were blocked from doing.
      await db.collection('quota_hits').doc(`${uid}_${today}`).set({
        uid,
        date: today,
        kind,
        capType: exceeded.type,
        cap: exceeded.cap,
        hitAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (e) {
      console.error('[generateAiText] could not write quota_hits record:', e);
    }
    const message = exceeded.type === 'user'
      ? `Daily cloud AI limit reached (${exceeded.cap}/day). Try again tomorrow, or use on-device AI if your phone supports it.`
      : 'Cloud AI is at capacity right now — please try again later.';
    throw new functions.https.HttpsError('resource-exhausted', message);
  }
}

exports.generateAiText = functions
  .runWith({
    // Default callable timeout (60s) was too tight for the newer Gemini
    // model on the "program" kind (longer prompt, 2048 output tokens) —
    // users saw it fail, then succeed on an immediate retry, which is the
    // signature of a timeout rather than a real error. Give it real
    // headroom; the client-side timeout in cloud_ai_service.dart is raised
    // to match.
    timeoutSeconds: 120,
  })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Sign-in required to use cloud AI.'
    );
  }
  // Anonymous auth used to be accepted here, but it's free to mint an
  // unlimited number of anonymous identities (see the "admin-restricted-
  // operation" incident on 2026-08-06 — this is unrelated to that bug,
  // just the same auth surface), which let anyone reset their own
  // per-uid daily cap in enforceUsageCap below just by re-authenticating.
  // Every caller of this function is already behind the app's Premium
  // paywall client-side (see lib/screens/meals_dashboard_screen.dart and
  // cloud_ai_consent_sheet.dart's ensureCloudSignIn), so requiring a real
  // Google account here adds no friction for legitimate users and closes
  // the free-identity abuse path. Client-side gating can be bypassed by a
  // scripted caller hitting this function directly, so this check is the
  // real enforcement — the client-side prompt is just UX.
  if (context.auth.token.firebase.sign_in_provider === 'anonymous') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Cloud AI requires signing in with your Google account — see Settings → Cloud & AI.'
    );
  }

  const kind = data.kind;

  // "mealPhoto" sends an image instead of a text description — validate
  // whichever field this kind actually needs before spending any quota.
  let description = '';
  let imageBase64 = '';
  if (kind === 'mealPhoto') {
    imageBase64 = (data.imageBase64 || '').toString();
    if (!imageBase64) {
      throw new functions.https.HttpsError('invalid-argument', 'imageBase64 is required.');
    }
    // The client already resizes to 1280px/85% quality before base64
    // encoding (see meals_screen.dart _scanPhoto), so a real photo lands
    // well under this — this is just a sanity cap against abuse.
    if (imageBase64.length > 8_000_000) {
      throw new functions.https.HttpsError('invalid-argument', 'Image too large.');
    }
  } else {
    description = (data.description || '').toString().trim();
    if (!description) {
      throw new functions.https.HttpsError('invalid-argument', 'description is required.');
    }
  }

  // Check quota before spending anything on Gemini — invalid-argument
  // errors above don't count against the cap, but a real generation
  // request does, even if the model output later fails to parse.
  await enforceUsageCap(context.auth.uid, kind);

  let contents;
  let maxOutputTokens;

  if (kind === 'meal') {
    maxOutputTokens = 512;
    contents = `You are a nutrition expert. Estimate the nutritional content of this meal.
The description may be in Norwegian or English.

Meal: "${description}"

Respond with ONLY a JSON object, no other text, in exactly this format:
{"calories": <kcal as integer>, "protein": <grams as integer>, "carbs": <grams as integer>, "fat": <grams as integer>}`;
  } else if (kind === 'foods') {
    maxOutputTokens = 768;
    contents = `Break this meal into individual foods with estimated weights.
The description may be in Norwegian or English.

Meal: "${description}"

Respond with ONLY a JSON array, no other text, in exactly this
format, using simple Norwegian food names:
[{"n": "<food name in Norwegian>", "g": <weight in grams as integer>}]`;
  } else if (kind === 'program') {
    const exerciseNames = data.exerciseNames;
    if (!Array.isArray(exerciseNames) || exerciseNames.length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'exerciseNames is required for kind "program".');
    }
    maxOutputTokens = 2048;
    const vocab = exerciseNames.join(', ');
    contents = `You are a strength training coach. Design a workout program from
this request. The request may be in Norwegian or English; reply
in the same language for "programName" and day "title" values.

Request: "${description}"

Rules:
- Only use exercise names from this exact list (copy them
  verbatim, do not translate or invent new ones):
  ${vocab}
- 2 to 6 exercises per day, 3 to 8 sets, 5 to 15 reps.
- Pick a sensible number of days per week from the request (if
  unclear, use 3).
- Balance muscle groups across the week; do not repeat the same
  exercise twice in one day.

Respond with ONLY a JSON object, no other text, in exactly this
format:
{"programName": "<short name>", "daysPerWeek": "<e.g. 3 days/week>",
 "days": [{"title": "<e.g. Day 1 - Legs>",
           "exercises": [{"name": "<from the list>", "sets": <int>, "reps": <int>}]}]}`;
  } else if (kind === 'mealPhoto') {
    // Mirrors MealEstimator.kt's describeImage prompt/output contract
    // exactly, so the client gets the same kind of short, comma-separated
    // description regardless of which path (on-device or cloud) answered.
    maxOutputTokens = 96;
    const photoPrompt = `List the foods and drinks visible in this photo with
approximate portion sizes, as one short comma-separated
description suitable for a nutrition log.
Respond with ONLY the description text.`;
    contents = [{
      role: 'user',
      parts: [
        { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } },
        { text: photoPrompt },
      ],
    }];
  } else {
    throw new functions.https.HttpsError('invalid-argument', `Unknown kind: ${kind}`);
  }

  // Note: "gemini-3.5-flash" (the Gemini Developer API / AI Studio name)
  // does NOT exist as a Vertex AI publisher model — Vertex has its own
  // catalog (gemini-2.5-flash, gemini-3-flash preview, etc). Using the
  // stable GA model here rather than a preview one.
  const model = 'gemini-2.5-flash';
  console.log(`[generateAiText] kind=${kind} model=${model} project=${GCLOUD_PROJECT}`);

  let response;
  try {
    response = await genAI.models.generateContent({
      model,
      contents,
      // Disable thinking: these are simple JSON-extraction tasks with no
      // real reasoning to do, and gemini-2.5-flash defaults to spending
      // part of maxOutputTokens on an internal "thinking" pass — with a
      // small budget that was eating the entire response, leaving the
      // actual JSON answer truncated (e.g. cut off after `{"calories":`).
      config: {
        temperature: 0.2,
        maxOutputTokens,
        thinkingConfig: { thinkingBudget: 0 },
      },
    });
  } catch (e) {
    console.error('[generateAiText] Vertex AI call failed:', e);
    throw new functions.https.HttpsError('internal', `Vertex AI error: ${e.message}`);
  }

  const text = response && response.text ? response.text : '';
  console.log('[generateAiText] response text:', text.slice(0, 500));

  return { text };
});

/**
 * Callable function for the Flutter app to generate a pairing code.
 * Returns a 6-digit code valid for 10 minutes.
 *
 * [DISABLED for this release]
 */
/*
exports.getPairingCode = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be signed in.');
    }

    const uid = context.auth.uid;
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = admin.firestore.Timestamp.now().toMillis() + (10 * 60 * 1000);

    await db.collection('pairing').doc(code).set({
        uid: uid,
        expiresAt: expiresAt
    });

    return { code: code };
});
*/

/**
 * HTTPS endpoint for the Garmin watch.
 * Handles pairing, status, and actions.
 *
 * [DISABLED for this release]
 */
/*
exports.garminApi = functions.https.onRequest(async (req, res) => {
    const { action, code, token } = req.query;

    // 1. Pairing (Code -> Permanent Token)
    if (action === 'pair') {
        if (!code) return res.status(400).send('Missing code');

        const pairingDoc = await db.collection('pairing').doc(code).get();
        if (!pairingDoc.exists) return res.status(404).send('Invalid code');

        const data = pairingDoc.data();
        if (data.expiresAt < admin.firestore.Timestamp.now().toMillis()) {
            await pairingDoc.ref.delete();
            return res.status(410).send('Code expired');
        }

        const newToken = crypto.randomUUID();
        await db.collection('garmin_links').doc(newToken).set({
            uid: data.uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // Clean up code
        await pairingDoc.ref.delete();

        return res.json({ token: newToken });
    }

    // 2. Auth Check (Token required for all other actions)
    if (!token) return res.status(401).send('Missing token');
    const linkDoc = await db.collection('garmin_links').doc(token).get();
    if (!linkDoc.exists) return res.status(403).send('Invalid token');
    const uid = linkDoc.data().uid;

    // 3. Actions
    if (action === 'status') {
        const userDoc = await db.collection('users').doc(uid).get();
        // Return basic fasting status (simplified for the watch)
        // We'll need to define where the "active fast" state lives in Firestore.
        // Assuming it's in a 'status' subcollection or just the last record.
        return res.json({ paired: true, uid: uid });
    }

    if (action === 'start') {
        // Create a new fast record in Firestore.
        // Existing CloudSyncService on phone will pick this up.
        const startTime = admin.firestore.Timestamp.now();
        const syncId = crypto.randomUUID();

        await db.collection('users').doc(uid).collection('fasts').doc(syncId).set({
            startTime: startTime.toMillis(),
            endTime: 0, // indicates active
            protocol: '16:8', // default
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return res.json({ success: true, syncId: syncId });
    }

    if (action === 'stop') {
        // Find the active fast and set endTime
        const fasts = await db.collection('users').doc(uid).collection('fasts')
            .where('endTime', '==', 0)
            .limit(1)
            .get();

        if (fasts.empty) return res.status(404).send('No active fast');

        const fastDoc = fasts.docs[0];
        await fastDoc.ref.update({
            endTime: admin.firestore.Timestamp.now().toMillis(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return res.json({ success: true });
    }

    res.status(400).send('Invalid action');
});
*/
