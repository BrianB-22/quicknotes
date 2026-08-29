# CloudSync — Idea for Future Discussion

**Status: not decided, not started. Planning notes only.**

An optional, paid, opt-in sync feature for QuickNotes — explicitly *not* part of the core app's identity. Local-only stays free and the default forever; this would be a separate mode layered on top.

## The pitch
Username/password-protected sync between a person's own devices (or potentially between different people, TBD — see Scope below), using Supabase as the backend. The password both authenticates the account *and* derives the key used to encrypt note text before it ever leaves the device — the server only ever stores ciphertext.

## The core tension
You can't have "password encrypts the data" and "forgot password? reset it" at the same time. If the password can be reset server-side, the encryption key is recoverable by the server, which means it isn't really end-to-end. Proton Mail/Drive are the model to copy: they generate a **recovery phrase** at signup (shown once, user's responsibility to save it) that can re-derive the encryption key to allow a password reset — but if you lose *both* the password and the phrase, the data is permanently gone. No exceptions, for anyone, ever. This needs to be communicated clearly at signup, not discovered later.

## Rough architecture
- **Backend**: Supabase — a `notes` table (ciphertext, salt, nonce, `user_id`, `updated_at`), Row Level Security so each account only ever sees its own rows.
- **Auth vs. encryption key must be cryptographically separated.** Derive two different keys from the same master password via distinct derivation paths (reusing the PBKDF2/AES-GCM approach already in `LockManager.swift`, just account-wide instead of per-note). Supabase should never see anything from which it could reconstruct the encryption key — otherwise the "we can't read your notes" claim is false.
- **Recovery phrase**: generated once at signup, shown with a clear "we cannot recover this for you" warning, used to re-derive the encryption key during a password reset.
- **Design fork to decide**: does *every* synced note get transparently encrypted before upload (simple mental model — "synced = encrypted, always"), or only notes the user has already locked with `LockManager`? Leaning toward the former; the latter is a weaker guarantee than "password encrypts the text at rest" implies.
- **Sync engine**: last-write-wins by *server-assigned* timestamp (not the device's own clock). On genuine conflicts (both devices changed a note since last sync), save the losing version as a duplicate ("Note (conflicted copy)") rather than silently discarding it — same pattern iCloud Drive/Dropbox use. Deletes need tombstones so a delete on one device doesn't get resurrected by a device that synced before the delete happened. Locked notes are the easy case here — their ciphertext is already opaque, so it's naturally whole-blob LWW with no partial-merge logic needed.
- **Session persistence**: Supabase refresh token in Keychain; the encryption key itself re-derived from the password each session (cached behind Touch ID, maybe), never the raw password stored.

## Monetization
- Charge for it — recurring, not one-time. A one-time fee doesn't track ongoing hosting cost as usage grows.
- Price target: ~$1.99/mo or ~$14.99/yr, matching Bear (closest comparable: a small note app where sync is the paid tier).
- Since QuickNotes ships as a direct notarized download (not App Store), no obligation to use Apple's in-app purchase / 30% cut — can bill directly.
- Use a merchant-of-record (LemonSqueezy or Paddle), not raw Stripe, so sales tax/VAT compliance across countries isn't a solo-dev burden.
- Keep local-only note-taking free forever; gate sync specifically behind the subscription.

## Why to be cautious
- This is a second product bolted onto the first, not a feature flag. The whole pitch of QuickNotes (and QuickCal) is "no accounts, no cloud, no subscriptions" — this directly contradicts that for whoever opts in.
- Real ongoing liability as the operator of a service holding other people's (encrypted) data: hosting cost that scales with usage, Supabase free-tier limits (project auto-pause after inactivity, DB/bandwidth/MAU caps), and permanent support burden — "I forgot my password and recovery phrase and lost everything" will generate angry messages no matter how clearly it's disclosed upfront.
- Scope clarity matters: syncing *your own* notes across *your own* devices is a much smaller problem than a genuine multi-tenant service for unrelated people (registration, abuse prevention, ToS/privacy policy, tax obligations).

## Rough effort sizing
Comparably sized to *everything already built in QuickNotes* (locking, Touch ID, the link editor, search, the whole release pipeline) — maybe bigger, because it adds three categories that don't exist in the app at all today:
1. **Networking** (Supabase client integration, push/pull sync)
2. **Account/auth lifecycle** (signup, login, session persistence, recovery-phrase-based password reset) — roughly the size of the whole lock/Touch ID feature on its own
3. **Payments** (checkout, webhook-driven entitlement, subscription lapse/renewal handling)

The sync/conflict logic itself (last-write-wins + conflicted copies + tombstones) is the *least* worrying part — bounded and well-understood. The real risk is (a) getting the auth/encryption key separation right, since a mistake there quietly breaks the entire privacy promise, and (b) testing — sync/conflict bugs are notoriously hard to fully exercise and genuinely need multiple devices to verify properly, which is a different (and much harder) kind of testing than anything the app has needed so far.

## Open questions for next time
- Single-user multi-device sync only, or genuinely multi-tenant for unrelated people?
- Exact recovery-phrase UX (word count, verification-on-signup flow, where/how it's shown)
- Whether per-note locking and account-level sync encryption compose, or whether sync encryption supersedes the need for per-note locks once an account is set up
- Whether this ships as a toggle in the existing app or as a genuinely separate build/SKU
