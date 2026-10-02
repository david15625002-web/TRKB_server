-- ============================================================================
--  TRKB · Permission functions and Row Level Security policies
--  Apply AFTER db/schema.sql.
--
--  Design rule (see docs/02): authorisation lives HERE, in the database, not in
--  application code. The app hides buttons a user cannot use, but that is UX.
--  This file is the security boundary. Every table has RLS enabled; there is no
--  table that is readable simply because someone is logged in.
--
--  Recursion note: every helper below is SECURITY DEFINER. That is mandatory,
--  not stylistic — a policy on `memberships` that itself queries `memberships`
--  through RLS would recurse infinitely. SECURITY DEFINER functions bypass RLS,
--  so each has an explicit `set search_path = public` to prevent search-path
--  hijacking, and none of them accepts a table name or SQL fragment as input.
-- ============================================================================

-- ============================================================================
--  SECTION 1 · PERMISSION PRIMITIVES
-- ============================================================================

create or replace function is_authenticated()
returns boolean language sql stable as $$
  select auth.uid() is not null;
$$;

-- An 'active' account is one a Ketua Kelas has approved. Pending accounts can
-- see their own profile and nothing else — this is the first containment line.
create or replace function is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
     where id = auth.uid() and status = 'active'
  );
$$;

create or replace function is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select is_super_admin from profiles where id = auth.uid()),
    false
  );
$$;

-- Does the current user hold `p_perm` over `p_unit`?
--
-- A grant at any ANCESTOR of the target unit counts, which is what makes the
-- hierarchy work: Ketua HIMA holds the role at program level, so the check
-- succeeds for every class below. A Ketua Kelas holds it at one class, so it
-- succeeds for that class and nothing else.
create or replace function has_perm(p_perm text, p_unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_super_admin()
      or exists (
        select 1
          from memberships m
          join roles r on r.id = m.role_id
         where m.user_id = auth.uid()
           and m.status  = 'active'
           and current_date >= m.period_start
           and (m.period_end is null or current_date <= m.period_end)
           and p_perm = any (r.permissions)
           and m.org_unit_id in (select id from org_unit_ancestors(p_unit))
      );
$$;

comment on function has_perm is
  'Scoped permission check. A grant at an ancestor unit covers all descendants, '
  'which is the entire mechanism behind Ketua HIMA > Kadiv > Ketua Kelas.';

-- Permission anywhere at all — for "can this person see the approval queue
-- menu item" style questions where the specific unit is not yet known.
create or replace function has_perm_anywhere(p_perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select is_super_admin()
      or exists (
        select 1 from memberships m join roles r on r.id = m.role_id
         where m.user_id = auth.uid() and m.status = 'active'
           and p_perm = any (r.permissions)
           and (m.period_end is null or current_date <= m.period_end)
      );
$$;

create or replace function is_member_of(p_unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m
     where m.user_id = auth.uid()
       and m.status  = 'active'
       and m.org_unit_id in (select id from org_unit_ancestors(p_unit))
  );
$$;

-- Units the current user can see data for: their own units plus everything
-- below any unit they hold a role in.
create or replace function my_visible_units()
returns setof uuid language sql stable security definer set search_path = public as $$
  select distinct d.id
    from memberships m
    cross join lateral org_unit_descendants(m.org_unit_id) d
   where m.user_id = auth.uid() and m.status = 'active';
$$;

create or replace function my_classes()
returns setof uuid language sql stable security definer set search_path = public as $$
  select m.org_unit_id
    from memberships m join org_units o on o.id = m.org_unit_id
   where m.user_id = auth.uid() and m.status = 'active' and o.type = 'class';
$$;

-- Rank of the current user's highest role (lowest number = most authority).
-- Used to stop a Kadiv from assigning someone Ketua HIMA.
create or replace function my_best_rank()
returns smallint language sql stable security definer set search_path = public as $$
  select coalesce(
    case when is_super_admin() then 0 else
      (select min(r.rank) from memberships m join roles r on r.id = m.role_id
        where m.user_id = auth.uid() and m.status = 'active'
          and (m.period_end is null or current_date <= m.period_end))
    end, 999)::smallint;
$$;

create or replace function is_room_member(p_room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from chat_members where room_id = p_room and user_id = auth.uid()
  );
$$;

create or replace function can_post_in_room(p_room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from chat_members cm
      join chat_rooms  r on r.id = cm.room_id
     where cm.room_id = p_room
       and cm.user_id = auth.uid()
       and r.archived_at is null
       and (
         not r.is_readonly                        -- ordinary room: anyone in it
         or cm.role in ('owner', 'moderator')     -- announcement: staff only
         or (r.org_unit_id is not null and has_perm('announcement.post', r.org_unit_id))
       )
  );
$$;

-- ============================================================================
--  SECTION 2 · ENABLE RLS EVERYWHERE
--
--  Done as one explicit block so that a new table added later without a policy
--  is immediately obvious: it will simply deny everything rather than leak.
-- ============================================================================

alter table org_units                enable row level security;
alter table roles                    enable row level security;
alter table profiles                 enable row level security;
alter table memberships              enable row level security;
alter table academic_terms           enable row level security;
alter table lecturers                enable row level security;
alter table subjects                 enable row level security;
alter table schedule_rules           enable row level security;
alter table schedule_sessions        enable row level security;
alter table tasks                    enable row level security;
alter table task_submissions         enable row level security;
alter table notification_preferences enable row level security;
alter table push_subscriptions       enable row level security;
alter table notification_jobs        enable row level security;
alter table notifications            enable row level security;
alter table chat_rooms               enable row level security;
alter table chat_members             enable row level security;
alter table chat_messages            enable row level security;
alter table chat_reactions           enable row level security;
alter table skills                   enable row level security;
alter table user_skills              enable row level security;
alter table projects                 enable row level security;
alter table project_collaborators    enable row level security;
alter table badges                   enable row level security;
alter table user_badges              enable row level security;
alter table user_stats               enable row level security;
alter table audit_log                enable row level security;

-- ============================================================================
--  SECTION 3 · ORG STRUCTURE & ROLES
-- ============================================================================

-- Anyone signed in may read the structure. A new student must be able to pick
-- their class on the registration screen before they belong to anything, so
-- this intentionally does not require is_active_user().
create policy org_units_read on org_units
  for select using (is_authenticated());

create policy org_units_insert on org_units
  for insert with check (has_perm('org.manage', coalesce(parent_id, id)));

create policy org_units_update on org_units
  for update using (has_perm('org.manage', id))
          with check (has_perm('org.manage', id));

-- Deleting a unit destroys its schedule, tasks and chat history. Super Admin
-- only, and the application must confirm twice before calling it.
create policy org_units_delete on org_units
  for delete using (is_super_admin());

create policy roles_read on roles
  for select using (is_authenticated());

-- Only a Super Admin edits the role catalogue itself — otherwise a Kadiv could
-- grant their own role the 'org.manage' permission and escalate.
create policy roles_write on roles
  for all using (is_super_admin()) with check (is_super_admin());

-- ============================================================================
--  SECTION 4 · PROFILES
--
--  The program is a directory: active students can see each other, because the
--  app is useless if you cannot look up who your sekretaris is. Pending and
--  suspended accounts are hidden from everyone except themselves and the
--  pengurus who must act on them.
-- ============================================================================

create policy profiles_read_self on profiles
  for select using (id = auth.uid());

create policy profiles_read_directory on profiles
  for select using (is_active_user() and status in ('active', 'alumni'));

-- Pengurus can see the pending applicants for units they administer.
create policy profiles_read_pending_for_approvers on profiles
  for select using (
    status = 'pending'
    and exists (
      select 1 from memberships m
       where m.user_id = profiles.id
         and m.status  = 'pending'
         and has_perm('member.approve', m.org_unit_id)
    )
  );

-- A user may create only their own profile row, as 'pending', never elevated.
create policy profiles_insert_self on profiles
  for insert with check (
    id = auth.uid()
    and status = 'pending'
    and profiles.is_super_admin = false
  );

create policy profiles_update_self on profiles
  for update using (id = auth.uid())
          with check (id = auth.uid());

create policy profiles_update_by_admin on profiles
  for update using (
    has_perm_anywhere('member.manage')
    and (my_best_rank() < 50 or is_super_admin())
  );


-- ---------------------------------------------------------------------------
--  Column-level guard on profiles.
--
--  RLS is ROW level. `profiles_update_self` correctly limits a student to their
--  own row — but within that row nothing stops them setting is_super_admin or
--  status = 'active'. That is a privilege-escalation path straight past the
--  approval flow, and it cannot be closed with a policy, because policies
--  cannot discriminate between columns.
--
--  So the privileged columns are frozen in a trigger: a non-privileged caller
--  updating their own row has those fields silently reset to their old values
--  rather than being thrown an error, because the common cause is a client
--  sending the whole object back, not an attack.
-- ---------------------------------------------------------------------------
create or replace function guard_profile_privileged_columns()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Super Admin may change anything.
  if is_super_admin() then
    return new;
  end if;

  -- Only someone holding member.manage may move another person's status,
  -- and nobody but a Super Admin may ever grant is_super_admin.
  new.is_super_admin := old.is_super_admin;

  if new.status is distinct from old.status
     and not has_perm_anywhere('member.manage') then
    new.status := old.status;
  end if;

  -- NIM is identity: changeable only before approval, or by a pengurus.
  if new.nim is distinct from old.nim
     and old.status <> 'pending'
     and not has_perm_anywhere('member.manage') then
    new.nim := old.nim;
  end if;

  -- Denormalised field owned by sync_primary_class().
  new.primary_class_id := old.primary_class_id;

  return new;
end $$;

create trigger profiles_guard_privileged
  before update on profiles
  for each row execute function guard_profile_privileged_columns();

-- ============================================================================
--  SECTION 5 · MEMBERSHIPS  (registration approval + role assignment)
-- ============================================================================

create policy memberships_read_self on memberships
  for select using (user_id = auth.uid());

-- Members of a unit can see who else is in it, and who holds which role. Role
-- transparency is a feature: students should know who their pengurus are.
create policy memberships_read_unit on memberships
  for select using (is_active_user() and is_member_of(org_unit_id));

create policy memberships_read_for_approvers on memberships
  for select using (has_perm('member.view', org_unit_id)
                 or has_perm('member.approve', org_unit_id));

-- A student may request to join a class, but only as themselves, only as
-- 'pending', and only with the plain 'anggota' role. Everything else — the role,
-- the approval, the dates — is for a pengurus to set.
create policy memberships_request_self on memberships
  for insert with check (
    user_id = auth.uid()
    and status = 'pending'
    and is_primary = false
    and decided_by is null
    and exists (select 1 from roles r where r.id = role_id and r.key = 'anggota')
  );

-- A pengurus may grant a membership in a unit they administer, but may never
-- grant a role at or above their own authority.
create policy memberships_insert_by_pengurus on memberships
  for insert with check (
    has_perm('member.manage', org_unit_id)
    and exists (
      select 1 from roles r
       where r.id = role_id
         and (r.rank > my_best_rank() or is_super_admin())
    )
  );

create policy memberships_update_by_pengurus on memberships
  for update using (
    has_perm('member.approve', org_unit_id)
    or has_perm('member.manage', org_unit_id)
  )
  with check (
    (has_perm('member.approve', org_unit_id) or has_perm('member.manage', org_unit_id))
    and exists (
      select 1 from roles r
       where r.id = role_id
         and (r.rank > my_best_rank() or is_super_admin())
    )
  );

-- A student may withdraw their own pending request, nothing more.
create policy memberships_delete_own_request on memberships
  for delete using (user_id = auth.uid() and status = 'pending');

create policy memberships_delete_by_admin on memberships
  for delete using (is_super_admin());

-- ============================================================================
--  SECTION 6 · ACADEMIC REFERENCE DATA
--
--  Terms, subjects and lecturers are program-wide reference data: readable by
--  everyone signed in, writable only by whoever holds the matching permission.
-- ============================================================================

create policy academic_terms_read on academic_terms
  for select using (is_authenticated());
create policy academic_terms_write on academic_terms
  for all using (has_perm_anywhere('term.manage'))
      with check (has_perm_anywhere('term.manage'));

create policy lecturers_read on lecturers
  for select using (is_active_user());
create policy lecturers_write on lecturers
  for all using (has_perm_anywhere('lecturer.manage'))
      with check (has_perm_anywhere('lecturer.manage'));

create policy subjects_read on subjects
  for select using (is_active_user());
create policy subjects_write on subjects
  for all using (has_perm('subject.manage', program_id))
      with check (has_perm('subject.manage', program_id));

-- ============================================================================
--  SECTION 7 · SCHEDULE  (feature 1)
--
--  This is where scoping earns its keep. The write policies key off class_id, so
--  the Sekretaris of TRKB-1 25 physically cannot touch TRKB-2 24's timetable —
--  not because the UI hides it, but because the row refuses to be written.
-- ============================================================================

-- Every active student may read every class's schedule. Deliberate: students
-- attend joint lectures, swap into other classes' sessions, and ask "kelas
-- sebelah jadwalnya kapan?". There is nothing sensitive in a timetable.
create policy schedule_rules_read on schedule_rules
  for select using (is_active_user());

create policy schedule_rules_write on schedule_rules
  for all using (has_perm('schedule.manage', class_id))
      with check (has_perm('schedule.manage', class_id));

create policy schedule_sessions_read on schedule_sessions
  for select using (is_active_user());

create policy schedule_sessions_write on schedule_sessions
  for all using (has_perm('schedule.manage', class_id))
      with check (has_perm('schedule.manage', class_id));

-- ============================================================================
--  SECTION 8 · TASKS  (feature 3)
--
--  Unlike schedules, tasks are visible only to the class they belong to.
--  A deadline list is more sensitive than a timetable, and cross-class
--  visibility would just be noise.
-- ============================================================================

create policy tasks_read_own_class on tasks
  for select using (
    deleted_at is null
    and (is_published or has_perm('task.manage', class_id))
    and (class_id in (select my_visible_units()) or has_perm('task.manage', class_id))
  );

create policy tasks_insert on tasks
  for insert with check (has_perm('task.manage', class_id));

create policy tasks_update on tasks
  for update using (has_perm('task.manage', class_id))
          with check (has_perm('task.manage', class_id));

-- Hard delete is not offered to pengurus; they set deleted_at (an UPDATE).
-- Keeping the row means a reminder already sent can still be explained.
create policy tasks_delete on tasks
  for delete using (is_super_admin());

-- Your checkbox is yours. No pengurus may edit another student's progress —
-- there is no policy granting it, by design.
create policy task_submissions_own on task_submissions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Pengurus may READ aggregate progress for their class (who has handed in), but
-- never write it. See docs/04 for the rationale on this being read-only.
create policy task_submissions_read_by_pengurus on task_submissions
  for select using (
    exists (
      select 1 from tasks t
       where t.id = task_submissions.task_id
         and has_perm('task.view_progress', t.class_id)
    )
  );

-- ============================================================================
--  SECTION 9 · NOTIFICATIONS
--
--  Strictly personal. There is no policy that lets any role read another
--  person's inbox or preferences, including Super Admin via the API. (A Super
--  Admin with direct SQL access can, of course — see docs/06 on honest privacy.)
-- ============================================================================

create policy notification_preferences_own on notification_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy push_subscriptions_own on push_subscriptions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy notifications_read_own on notifications
  for select using (user_id = auth.uid());

-- Only mark-as-read is permitted from the client; content is written by
-- triggers and the service role.
create policy notifications_update_own on notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy notifications_delete_own on notifications
  for delete using (user_id = auth.uid());

-- The outbox is server-only. Students may inspect their own queued reminders
-- (useful for "why didn't I get a notification?") but may not write to it.
create policy notification_jobs_read_own on notification_jobs
  for select using (user_id = auth.uid());

-- ============================================================================
--  SECTION 10 · CHAT  (feature 5)
-- ============================================================================

-- Room discovery: your rooms, plus public rooms you could choose to join.
create policy chat_rooms_read on chat_rooms
  for select using (
    is_room_member(id)
    or (is_active_user() and kind = 'public' and not is_private)
  );

create policy chat_rooms_insert on chat_rooms
  for insert with check (
    -- Anyone active may start a public room…
    (is_active_user() and kind = 'public' and created_by = auth.uid())
    -- …unit rooms need the chat permission for that unit.
    or (org_unit_id is not null and has_perm('chat.manage', org_unit_id))
  );

create policy chat_rooms_update on chat_rooms
  for update using (
    exists (select 1 from chat_members cm
             where cm.room_id = chat_rooms.id and cm.user_id = auth.uid()
               and cm.role in ('owner', 'moderator'))
    or (org_unit_id is not null and has_perm('chat.manage', org_unit_id))
  );

create policy chat_members_read on chat_members
  for select using (is_room_member(room_id));

-- Join a public room yourself; private rooms require a moderator to add you.
create policy chat_members_join_public on chat_members
  for insert with check (
    user_id = auth.uid()
    and exists (select 1 from chat_rooms r
                 where r.id = room_id and r.kind = 'public' and not r.is_private)
  );

create policy chat_members_add_by_mod on chat_members
  for insert with check (
    exists (select 1 from chat_members cm
             where cm.room_id = chat_members.room_id and cm.user_id = auth.uid()
               and cm.role in ('owner', 'moderator'))
  );

-- Update your own row only (last_read_at, muted_until, is_pinned).
create policy chat_members_update_own on chat_members
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy chat_members_leave on chat_members
  for delete using (
    user_id = auth.uid()
    or exists (select 1 from chat_members cm
                where cm.room_id = chat_members.room_id and cm.user_id = auth.uid()
                  and cm.role in ('owner', 'moderator'))
  );

create policy chat_messages_read on chat_messages
  for select using (is_room_member(room_id));

create policy chat_messages_insert on chat_messages
  for insert with check (
    author_id = auth.uid()
    and can_post_in_room(room_id)
    and deleted_at is null
  );

-- Edit your own message, and only the body.
create policy chat_messages_update_own on chat_messages
  for update using (author_id = auth.uid() and deleted_at is null)
          with check (author_id = auth.uid());

-- Moderators and unit pengurus may soft-delete (redaction happens in a trigger).
create policy chat_messages_moderate on chat_messages
  for update using (
    exists (
      select 1 from chat_members cm
        left join chat_rooms r on r.id = cm.room_id
       where cm.room_id = chat_messages.room_id
         and cm.user_id = auth.uid()
         and (cm.role in ('owner', 'moderator')
              or (r.org_unit_id is not null and has_perm('chat.moderate', r.org_unit_id)))
    )
  );

create policy chat_reactions_read on chat_reactions
  for select using (
    exists (select 1 from chat_messages m
             where m.id = chat_reactions.message_id and is_room_member(m.room_id))
  );

create policy chat_reactions_write_own on chat_reactions
  for all using (user_id = auth.uid())
      with check (
        user_id = auth.uid()
        and exists (select 1 from chat_messages m
                     where m.id = message_id and is_room_member(m.room_id))
      );

-- ============================================================================
--  SECTION 11 · PROFILE EXTRAS  (feature 4)
-- ============================================================================

create policy skills_read on skills
  for select using (is_authenticated());
create policy skills_write on skills
  for all using (has_perm_anywhere('skill.manage'))
      with check (has_perm_anywhere('skill.manage'));

create policy user_skills_read on user_skills
  for select using (is_active_user());
create policy user_skills_own on user_skills
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy projects_read on projects
  for select using (
    (is_public and is_active_user())
    or owner_id = auth.uid()
    or exists (select 1 from project_collaborators pc
                where pc.project_id = projects.id and pc.user_id = auth.uid())
  );

create policy projects_own on projects
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy project_collaborators_read on project_collaborators
  for select using (is_active_user());

create policy project_collaborators_manage on project_collaborators
  for all using (
    exists (select 1 from projects p
             where p.id = project_collaborators.project_id and p.owner_id = auth.uid())
  )
  with check (
    exists (select 1 from projects p
             where p.id = project_collaborators.project_id and p.owner_id = auth.uid())
  );

create policy badges_read on badges
  for select using (is_authenticated());
create policy badges_write on badges
  for all using (is_super_admin()) with check (is_super_admin());

-- Badges are public: that is the point of them.
create policy user_badges_read on user_badges
  for select using (is_active_user());

-- Awarded by server-side rules only. No client-side insert policy exists, so a
-- student cannot grant themselves a badge.

create policy user_stats_read on user_stats
  for select using (is_active_user());

-- Recomputed by trigger from task_submissions; never written by a client.

-- ============================================================================
--  SECTION 12 · AUDIT LOG
-- ============================================================================

create policy audit_log_read on audit_log
  for select using (
    is_super_admin()
    or (org_unit_id is not null and has_perm('audit.view', org_unit_id))
  );

-- Append-only: written exclusively by SECURITY DEFINER triggers. No INSERT,
-- UPDATE or DELETE policy exists for clients, which is what makes the log
-- trustworthy — a pengurus cannot erase evidence of their own change.

-- ============================================================================
--  SECTION 13 · STORAGE BUCKET POLICIES
--
--  Buckets to create in the Supabase dashboard (or via the CLI):
--    avatars        public read   — small, cached, harmless
--    banners        public read
--    project-media  public read
--    chat-media     PRIVATE      — served only via short-lived signed URLs,
--                                  because a leaked chat image URL is a real
--                                  privacy failure
--    task-files     PRIVATE      — attachment files for tugas
--
--  Convention: the first path segment is always the owning user's uuid, which
--  is what the policies below key on.
-- ============================================================================

-- create policy "avatar public read" on storage.objects
--   for select using (bucket_id = 'avatars');
--
-- create policy "avatar owner write" on storage.objects
--   for insert with check (
--     bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
--   );
--
-- create policy "chat media read if room member" on storage.objects
--   for select using (
--     bucket_id = 'chat-media'
--     and is_room_member(((storage.foldername(name))[1])::uuid)
--   );
--
-- create policy "chat media upload if can post" on storage.objects
--   for insert with check (
--     bucket_id = 'chat-media'
--     and can_post_in_room(((storage.foldername(name))[1])::uuid)
--   );
