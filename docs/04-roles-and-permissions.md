# 04 · Roles & Permissions

Implementation: [`db/policies.sql`](../db/policies.sql).
Role catalogue: [`db/seed.sql`](../db/seed.sql) section 1.

## The one-sentence version

A role is granted **at an org unit**, and it applies to that unit and everything
beneath it — so Ketua HIMA holds a permission once at program level and it
covers every class, while Ketua Kelas holds it at one class and covers nothing
else.

## The mechanism

```sql
create function has_perm(p_perm text, p_unit uuid) returns boolean as $$
  select is_super_admin()
      or exists (
        select 1 from memberships m join roles r on r.id = m.role_id
         where m.user_id = auth.uid()
           and m.status  = 'active'
           and current_date between m.period_start
                                and coalesce(m.period_end, 'infinity'::date)
           and p_perm = any (r.permissions)
           and m.org_unit_id in (select id from org_unit_ancestors(p_unit))
      );
$$;
```

Four things are being checked at once, and all four matter:

1. **The permission** — does any held role grant this key?
2. **The scope** — is the grant at the target unit or an ancestor of it?
3. **The time** — is the membership's period currently open? An expired
   kepengurusan loses access automatically, with no cleanup job.
4. **The status** — `active` only. A `pending` applicant has no permissions.

Verified behaviour:

| Subject | Target | `has_perm('task.manage', …)` |
|---|---|---|
| Budi, Ketua Kelas TRKB-1 25 | TRKB-1 25 | **true** |
| Budi, Ketua Kelas TRKB-1 25 | TRKB-2 25 | **false** |
| Sari, Anggota TRKB-1 25 | TRKB-1 25 | **false** |

And at the table level, which is what actually counts:

```
TEST 7: ketua kelas created a task in their own class        PASS
TEST 8: RLS blocked the cross-class write                    PASS
TEST 9: RLS blocked the anggota                              PASS
```

## Permission keys

Stable strings in `roles.permissions[]`. Adding a key is a seed update, not a
migration.

| Key | Grants |
|---|---|
| `org.manage` | Create and edit org units (divisions, committees, classes) |
| `role.manage` | Edit the role catalogue itself — **Super Admin only** |
| `term.manage` | Create academic terms, mark one current |
| `subject.manage` | Maintain the subject list |
| `lecturer.manage` | Maintain lecturer records |
| `member.view` | See member lists and who holds which role |
| `member.approve` | Approve or reject join requests |
| `member.manage` | Assign roles, end memberships |
| `schedule.manage` | Create and edit jadwal for a unit |
| `task.manage` | Create and edit tugas for a unit |
| `task.view_progress` | See who has handed in (read-only, always) |
| `announcement.post` | Post in read-only announcement channels |
| `chat.manage` | Create unit rooms |
| `chat.moderate` | Delete others' messages |
| `skill.manage` | Curate the skill tag list |
| `audit.view` | Read the audit log |

## Matrix

`●` granted · `−` not granted · scope column says *where* it applies

| | Scope | org | role | term | subj | lect | m.view | m.appr | m.mng | sched | task | t.prog | annc | chat.m | chat.mod | skill | audit |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Super Admin** | system | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| **Ketua HIMA** | program | ● | − | − | − | − | ● | ● | ● | − | − | ● | ● | ● | ● | − | ● |
| **Wakil Ketua HIMA** | program | − | − | − | − | − | ● | ● | ● | − | − | ● | ● | ● | ● | − | − |
| **Sekretaris HIMA** | program | − | − | ● | ● | ● | ● | ● | − | − | − | − | ● | ● | − | − | − |
| **Bendahara HIMA** | program | − | − | − | − | − | ● | − | − | − | − | − | ● | − | − | − | − |
| **Kadiv** | division | − | − | − | − | − | ● | − | ● | − | − | − | ● | ● | ● | − | − |
| **Sekretaris Divisi** | division | − | − | − | − | − | ● | − | − | − | − | − | ● | − | − | − | − |
| **Ketua Kelas** | class | − | − | − | − | − | ● | ● | ● | ● | ● | ● | ● | − | ● | − | − |
| **Sekretaris Kelas** | class | − | − | − | − | − | ● | ● | − | ● | ● | ● | ● | − | − | − | − |
| **Bendahara Kelas** | class | − | − | − | − | − | ● | − | − | − | − | − | − | − | − | − | − |
| **Anggota Divisi** | division | − | − | − | − | − | ● | − | − | − | − | − | − | − | − | − | − |
| **Anggota** | class | − | − | − | − | − | − | − | − | − | − | − | − | − | − | − | − |

Read the Ketua Kelas row carefully: it grants `schedule.manage` and
`task.manage`, but **scoped to one class**. The same row for Ketua HIMA grants
neither — a program head has no business rewriting a specific class's timetable,
and if they genuinely need to, they can grant themselves the class role and the
audit log will record it.

## Anti-escalation

Three separate mechanisms, because this is where a role system usually breaks.

**1 · Rank ordering.** You may only assign a role of strictly higher rank
(lower authority) than your own best rank:

```sql
create policy memberships_insert_by_pengurus on memberships
  for insert with check (
    has_perm('member.manage', org_unit_id)
    and exists (select 1 from roles r
                 where r.id = role_id
                   and (r.rank > my_best_rank() or is_super_admin()))
  );
```

So a Kadiv (30) cannot appoint anyone Ketua HIMA (10), or even another Kadiv.

**2 · The role catalogue is Super-Admin-only.** Without this, a Kadiv with
`member.manage` could simply add `org.manage` to their own role's permission
array and escalate in one UPDATE. Hence:

```sql
create policy roles_write on roles
  for all using (is_super_admin()) with check (is_super_admin());
```

**3 · Column-level guard on `profiles`.** This one was a genuine bug caught
during review, and it is worth understanding because it is a trap in every RLS
design.

`profiles_update_self` correctly restricts a student to their own row:

```sql
create policy profiles_update_self on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());
```

But RLS is **row** level. Within their own row, nothing stopped a student
running:

```sql
update profiles set is_super_admin = true, status = 'active' where id = auth.uid();
```

That is total escalation, and it walks straight past the Ketua-Kelas approval
flow. No policy can fix it, because policies cannot discriminate between
columns. The fix is a `BEFORE UPDATE` trigger that freezes the privileged
fields:

```sql
new.is_super_admin := old.is_super_admin;           -- always
if new.status is distinct from old.status
   and not has_perm_anywhere('member.manage') then
  new.status := old.status;
end if;
```

Values are silently reset rather than raising an error, because the common cause
is a client PATCHing the whole object back, not an attack.

Verified: Sari attempting `set is_super_admin = true, status = 'active',
bio = 'Halo!'` ends with `is_super_admin = false` and the bio change kept.

## Registration flow

```
  Student                        System                     Ketua/Sekretaris Kelas
     │                              │                                 │
     ├─ sign in with campus email ─▶│                                 │
     │   @mahasiswa.unikom.ac.id    │                                 │
     │                              ├─ profile created, status=pending │
     ├─ enter NIM, pick class ─────▶│                                 │
     │                              ├─ membership (pending, 'anggota')─▶ push notification
     │                              │                                 │
     │         ┌────────────────────┤◄──────── approve / reject ───────┤
     │         │                    │                                 │
     │◄────────┤ status=active      ├─ auto-enrol in class chat room   │
     │         │ push: "diterima"   ├─ enqueue reminders for open tugas│
```

Two independent gates: the campus email domain stops outsiders, and a human
approval stops a student from joining the wrong class — accidentally or
otherwise.

The insert policy pins down exactly what a student may request:

```sql
create policy memberships_request_self on memberships
  for insert with check (
    user_id = auth.uid()
    and status = 'pending'
    and is_primary = false
    and decided_by is null
    and exists (select 1 from roles r where r.id = role_id and r.key = 'anggota')
  );
```

They cannot self-approve, cannot request a role other than `anggota`, and cannot
forge the decision trail.

## Handover each kepengurusan

```sql
-- End the outgoing Ketua Kelas
update memberships set period_end = '2027-01-31', status = 'ended'
 where user_id = '<outgoing>' and org_unit_id = '<class>'
   and role_id = (select id from roles where key = 'ketua_kelas');

-- Start the incoming one
insert into memberships (user_id, org_unit_id, role_id, status, period_start)
values ('<incoming>', '<class>',
        (select id from roles where key = 'ketua_kelas'), 'active', '2027-02-01');
```

No password is shared, nothing is deleted, access expires on its own date, and
the history of who led the class is permanent. In the app this is two taps.

## Testing

`db/tests/02-permissions.sql` runs as a non-owner role (`authenticated`) with
`request.jwt.claim.sub` set — this is essential, because **RLS is not enforced
for superusers or table owners**. A test that runs as `postgres` proves nothing
and will happily report that your policies work when they do not.

Planned additions for Phase 1, in pgTAP: one test per policy, plus negative
tests for each escalation path above.
