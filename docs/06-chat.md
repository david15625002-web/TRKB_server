# 06 · Chat

## Room types

| Kind | Created | Membership | Who can post |
|---|---|---|---|
| `class` | Automatically when a class is created | Every approved member, automatically | Everyone in it |
| `division` | Automatically when a division is created | Division members | Everyone in it |
| `announcement` | By a pengurus | Everyone in the unit | Only `announcement.post` holders |
| `public` | By any active student | Opt-in, discoverable | Everyone who joined |
| `dm` | On first message | Exactly two people | Both |

Class and division rooms are **auto-provisioned by trigger** — there is never an
empty-state problem where a new class has no room and nobody knows who should
make one:

```sql
create trigger org_units_provision_room
  after insert on org_units
  for each row execute function provision_unit_room();

create trigger memberships_enrol_chat
  after insert or update of status on memberships
  for each row execute function enrol_member_in_unit_room();
```

Approve a student into TRKB-1 25 and they are in the TRKB-1 25 room before they
finish reading the approval notification.

## DMs can only exist once per pair

The obvious bug in every hand-rolled DM feature is two threads for the same two
people, created when both tap "message" at the same moment. Prevented with a
canonical key:

```sql
create function dm_key_for(a uuid, b uuid) returns text immutable as $$
  select least(a::text, b::text) || '|' || greatest(a::text, b::text);
$$;

-- chat_rooms.dm_key is UNIQUE
```

`open_dm(other_user)` looks up the key and returns the existing room, or creates
it. Sorting the pair makes the key identical regardless of who initiates.

## Privacy: stated plainly

**Messages are stored unencrypted. Anyone with direct database access — which
means the Super Admin, i.e. you — can read them, including DMs.**

This will be shown in the app, in the room list and in a one-time notice at
first chat use. Not in a terms-of-service nobody reads: on screen, in plain
Indonesian.

Why v1 is built this way, and why saying so matters:

- E2E encryption needs key management, multi-device key sync, and a lost-device
  recovery story. It is a semester project in itself (and a genuinely good
  skripsi topic — noted in `docs/01` and `docs/11`).
- Moderation requires readable content. A class app with no moderation path is a
  liability the first time someone is harassed in it.
- **An app that implies privacy it does not provide is worse than one that
  admits it.** A student who knows DMs are readable will use WhatsApp for private
  things, which is the correct outcome. A student who wrongly believes they are
  private can be genuinely harmed.

What the RLS policies *do* enforce, which is not nothing:

| Guarantee | Mechanism |
|---|---|
| Non-members cannot read a room, including via the API or Realtime | `chat_messages_read` requires `is_room_member(room_id)` |
| Private rooms are invisible in discovery | `chat_rooms_read` excludes non-member private rooms |
| Super Admin has **no API-level** policy granting access to others' DMs | No such policy exists in `policies.sql` |
| Deleted means deleted | `redact_deleted_message` nulls `body`, `attachments`, `mentions` |
| Chat images are not world-readable | Private storage bucket + signed URLs keyed on room membership |

That fourth row matters: the Super Admin's access is via direct SQL, not through
the application. There is no admin screen that reads DMs, so reading them
requires deliberately opening a database console — an act, not an accident.

## Realtime

Supabase Realtime streams `chat_messages`, `chat_reactions` and `notifications`
straight from Postgres logical replication, **with RLS applied to the stream**.
A client subscribed to `chat_messages` receives only rows from rooms it belongs
to. There is no second system to keep in sync, and no way for a subscription
filter bug to leak another class's messages.

Send path:

```
 1. Optimistic render with a temporary id
 2. INSERT into chat_messages via supabase-js (RLS checks can_post_in_room)
 3. Realtime echo arrives → reconcile with the real row
 4. On error → mark the bubble failed, offer retry
```

## Moderation

| Action | Who |
|---|---|
| Delete own message | Author |
| Edit own message (body only) | Author |
| Delete anyone's message | Room `owner`/`moderator`, or `chat.moderate` on the unit |
| Remove a member | Room `owner`/`moderator` |
| Archive a room | Room `owner`, or `chat.manage` on the unit |

Ketua Kelas holds `chat.moderate` on their class, so there is always a reachable
human who can remove something bad from a class room without needing you.

## Deliberately not in v1

| Feature | Why |
|---|---|
| Voice notes | Storage cost + no practical moderation for audio |
| Arbitrary file sharing | Abuse surface; tugas attachments go on the task instead |
| Message search across all rooms | Trigram index exists; the UI is deferred |
| Threads | Reply-to is enough for a class of 40 |
| Typing indicators | Realtime chatter for near-zero value |
| Read receipts per message | `chat_members.last_read_at` costs one row instead of one row per message per person |

## The honest risk

**Your classmates already have a WhatsApp group, and it works.** Chat is the most
expensive feature here and the least likely to displace an incumbent habit.

The realistic outcome is that the *announcement* channel gets used (because it is
tied to tasks and schedules, which only this app has) while free discussion
stays on WhatsApp. That is fine, and it is why announcement channels are
configured to work well with zero free-chat adoption.

If chat usage is near zero after one semester, the right move is to cut DMs and
public rooms and keep only announcements. That decision is deliberately cheap:
room kinds are an enum, and removing one does not touch the schedule, task, or
role systems at all.
