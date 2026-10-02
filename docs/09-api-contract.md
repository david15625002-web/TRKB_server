# 09 · API Contract

Most reads go **straight to PostgREST** (Supabase's auto-generated API) with RLS
as the authorisation layer. Only operations needing server-side logic, secrets,
or multi-step validation get a Server Action or Route Handler.

The rule for deciding: **if RLS alone expresses the rule, there is no endpoint.**
Writing a wrapper that re-implements a policy in TypeScript doubles the places a
bug can hide.

## Direct PostgREST (no custom endpoint)

```ts
// Jadwal for a week — RLS restricts to classes the user may see
supabase.from('schedule_sessions')
  .select('*, subject:subjects(name,color,code), lecturer:lecturers(full_name)')
  .eq('class_id', classId)
  .gte('session_date', senin).lte('session_date', jumat)
  .order('starts_at');

// Mark a task done — your own row, enforced by task_submissions_own
supabase.from('task_submissions')
  .upsert({ task_id, user_id: me, state: 'done' }, { onConflict: 'task_id,user_id' });

// Send a message — RLS calls can_post_in_room()
supabase.from('chat_messages').insert({ room_id, author_id: me, body });

// Update your own theme
supabase.from('profiles')
  .update({ theme_preset: 'blueprint', theme_mode: 'light' }).eq('id', me);
```

## RPCs (in-database functions)

| Function | Returns | Why it is an RPC |
|---|---|---|
| `get_beranda(p_date date)` | `jsonb` | One round trip for the whole dashboard instead of six. `SECURITY INVOKER`, so RLS still applies. |
| `open_dm(p_other uuid)` | `uuid` | Must look up or create atomically, or two taps make two threads. |
| `semester_of(entry_year, term_id)` | `smallint` | Derived everywhere; must have exactly one definition. |
| `generate_sessions_for_rule(rule_id)` | `int` | Called by trigger and by cron. |
| `enqueue_task_reminders(task_id)` | `int` | Trigger-driven; exposed for manual re-send. |
| `has_perm(perm, unit)` | `boolean` | Lets the UI ask the same question the policies ask. |

`get_beranda` response:

```json
{
  "date": "2026-10-02",
  "class": { "id": "…", "code": "TRKB-1 25", "name": "…", "semester": 3 },
  "sessions": [{ "id": "…", "subject": "Mikrokontroler", "subject_color": "#f87171",
                 "lecturer": "Ir. …", "room": "Lab Robotika 1", "kind": "praktikum",
                 "starts_at": "2026-10-02T00:00:00Z", "ends_at": "…",
                 "status": "scheduled", "note": null }],
  "tasks":    [{ "id": "…", "title": "Laporan Praktikum", "kind": "praktikum",
                 "priority": "urgent", "subject": "Mikrokontroler",
                 "due_at": "…", "state": "todo", "submit_channel": "Kumpulkan di kelas" }],
  "unread_notifs": 3, "unread_chats": 1,
  "stats": { "tasks_on_time": 38, "streak_current": 12, "…": 0 }
}
```

## Server Actions

Mutations that need validation beyond what a CHECK constraint can express, or
that must do several things in one unit of work.

### `createTask(input)`

```ts
const CreateTask = z.object({
  classId:       z.string().uuid(),
  subjectId:     z.string().uuid().optional(),
  lecturerId:    z.string().uuid().optional(),
  title:         z.string().trim().min(3).max(160),
  description:   z.string().max(4000).optional(),
  kind:          z.enum(['tugas','quiz','ujian','praktikum','proyek','presentasi']),
  priority:      z.enum(['low','normal','high','urgent']).default('normal'),
  dueAt:         z.string().datetime(),
  submitChannel: z.string().max(120).optional(),
  linkUrl:       z.string().url().startsWith('https://').optional(),
  publish:       z.boolean().default(true),
});
```

Runs **as the user**, not the service role, so `tasks_insert` is the authority on
whether this person may write to that class. On success the insert trigger
enqueues reminders for every member.

```ts
// → { ok: true, taskId, remindersQueued: 76 }
// → { ok: false, error: 'FORBIDDEN' | 'VALIDATION' | 'DUE_IN_PAST' }
```

Returning `remindersQueued` is deliberate: the UI can say *"pengingat dijadwalkan
untuk 38 anggota"*, which makes an invisible background mechanism legible.

### `importSchedule(classId, termId, rows)`

Bulk jadwal import. Three phases so a tired sekretaris cannot half-import a
semester:

1. **Parse** — map CSV columns, fuzzy-match subject and lecturer names via
   trigram similarity, report unmatched rows.
2. **Validate** — detect clashes *before* writing, by checking the proposed set
   against itself and against existing rules.
3. **Commit** — insert rules in one transaction; triggers generate sessions.

```ts
// → { ok: true, rulesCreated: 8, sessionsGenerated: 118, warnings: [...] }
// → { ok: false, stage: 'validate', conflicts: [{ row: 4, with: 'TRKB-301', day: 1 }] }
```

### `decideMembership(membershipId, decision, note?)`

Approve or reject a join request. Checks `member.approve` via RLS, writes the
decision trail, and on approval: sets `status = 'active'`, flips the profile to
active, enrols the student in the class chat room (trigger), and enqueues
reminders for already-open tasks.

### `assignRole(userId, orgUnitId, roleId, periodStart, periodEnd?)`

Guarded by the rank rule in `memberships_insert_by_pengurus`. Returns
`RANK_TOO_HIGH` when someone attempts to assign at or above their own authority.

### `uploadAvatar` / `uploadChatImage`

Validates by **magic bytes, not file extension**, caps dimensions, strips EXIF
(a photo's embedded GPS location is a real privacy leak), and writes to the
`<uid>/` or `<room>/` prefix the storage policies key on.

## Route Handlers

| Route | Method | Auth | Purpose |
|---|---|---|---|
| `/api/push/subscribe` | POST | user | Store a Web Push subscription |
| `/api/push/unsubscribe` | POST | user | Remove one |
| `/api/cron/dispatch` | POST | cron secret | Drain `notification_jobs` |
| `/api/cron/enqueue-class` | POST | cron secret | Rolling 48h class reminders |
| `/api/cron/health` | GET | cron secret | Watchdog: stuck-queue depth |
| `/api/ics/[classId]` | GET | signed token | Calendar feed for Google Calendar |

Cron routes authenticate with a shared secret in a header, and **must** return
200 quickly — the drain reports its own progress rather than holding the request
open until the queue is empty.

## Realtime subscriptions

```ts
supabase.channel(`room:${roomId}`)
  .on('postgres_changes',
      { event: '*', schema: 'public', table: 'chat_messages', filter: `room_id=eq.${roomId}` },
      onMessage)
  .subscribe();

supabase.channel(`notif:${me}`)
  .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${me}` },
      onNotification)
  .subscribe();
```

The `filter` is a performance hint, not a security boundary — **RLS is applied to
the replication stream**, so a client that removed the filter would still receive
only rows it is allowed to see.

## Errors

One shape everywhere, so the UI has one error path:

```ts
type Err = {
  ok: false,
  error: 'VALIDATION' | 'FORBIDDEN' | 'NOT_FOUND' | 'CONFLICT' | 'RATE_LIMITED' | 'SERVER',
  message: string,          // Indonesian, safe to show the user
  fields?: Record<string,string>,
  detail?: string,          // developer-facing, never rendered
}
```

Postgres error codes map as: `42501` → `FORBIDDEN`, `23505` → `CONFLICT`,
`23P01` (exclusion violation, i.e. a schedule clash) → `CONFLICT` with a specific
Indonesian message naming the clashing slot.

## Rate limits

| Action | Limit |
|---|---|
| Create task | 20 / hour / user |
| Send message | 30 / minute / user |
| Join request | 5 / day / user |
| Avatar upload | 10 / day / user |
| Push subscribe | 20 / day / user |

Enforced at the edge via Upstash Redis, or an in-database counter table if the
free tier proves sufficient.

## Conventions

- Timestamps are **ISO-8601 UTC** on the wire; the client renders in
  `Asia/Jakarta`. The server never emits naive local time.
- IDs are UUID v4 strings.
- Pagination is keyset (`?after=<cursor>&limit=50`), not offset — offset
  pagination duplicates and skips rows in a live chat.
- Lists return `{ items, nextCursor }`.
- Writes are idempotent where it is cheap: a client-supplied `requestId` on
  `createTask` makes a double-tapped submit button harmless.
