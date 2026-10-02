-- ============================================================================
--  TRKB Student Information System — PostgreSQL schema
--  Target: Supabase (PostgreSQL 15+)
--  Row Level Security policies live in db/policies.sql — apply that AFTER this.
--
--  Conventions
--    * Identifiers, comments and documentation in English.
--    * Domain vocabulary kept in Indonesian where it is the real term
--      (tugas, jadwal, ketua_kelas) — translating those loses meaning.
--    * All timestamps are timestamptz. The app's display timezone is
--      Asia/Jakarta (WIB, UTC+7); never store naive local time.
--    * Every table carries created_at; mutable tables carry updated_at
--      maintained by the touch_updated_at() trigger.
--    * Deletes are soft where history matters (chat, tasks), hard where it
--      does not (reactions, push subscriptions).
-- ============================================================================

create extension if not exists "pgcrypto";    -- gen_random_uuid()
create extension if not exists "btree_gist";  -- exclusion constraints on ranges
create extension if not exists "pg_trgm";     -- fuzzy search on names/subjects
create extension if not exists "unaccent";    -- diacritic-insensitive search

-- ============================================================================
--  SECTION 1 · ENUMERATED TYPES
-- ============================================================================

-- Account lifecycle. 'pending' users have authenticated but are not yet
-- approved into a class, and can see nothing but their own pending screen.
create type user_status as enum ('pending', 'active', 'suspended', 'alumni');

-- The org tree is generic on purpose: the Super Admin can add divisions and
-- committees without a migration. Only 'program' is a root.
create type org_unit_type as enum ('program', 'class', 'division', 'committee');

-- Which level of the tree a role may be granted at. Prevents nonsense like
-- assigning 'ketua_kelas' at program level.
create type role_scope as enum ('system', 'program', 'division', 'class');

create type academic_term_kind as enum ('ganjil', 'genap', 'pendek');

create type schedule_kind as enum ('teori', 'praktikum', 'responsi', 'seminar');

-- Per-occurrence status. A cancelled class keeps its row so that students who
-- already saw it understand why it vanished, and so reminders can be revoked.
create type session_status as enum ('scheduled', 'moved', 'cancelled', 'held');

create type task_kind as enum ('tugas', 'quiz', 'ujian', 'praktikum', 'proyek', 'presentasi');

create type task_priority as enum ('low', 'normal', 'high', 'urgent');

-- Personal, per-student progress. Deliberately separate from the task itself:
-- one student marking something done must never mutate shared state.
create type submission_state as enum ('todo', 'in_progress', 'submitted', 'done', 'skipped');

create type membership_status as enum ('pending', 'active', 'rejected', 'ended');

create type room_kind as enum ('class', 'division', 'announcement', 'public', 'dm');

create type room_member_role as enum ('owner', 'moderator', 'member');

create type message_kind as enum ('text', 'image', 'system');

create type notification_channel as enum ('inapp', 'push', 'email');

create type job_state as enum ('queued', 'sending', 'sent', 'failed', 'cancelled', 'suppressed');

-- Accent colour the student picks; every UI token follows it. The three are
-- Duolingo brand colours (Owl Green, Eel Blue, Streak Orange), each
-- contrast-checked in both light and dark (see docs/08).
create type accent_seed as enum ('green', 'blue', 'orange');

create type theme_mode as enum ('light', 'dark', 'system');

-- ============================================================================
--  SECTION 2 · SHARED HELPERS
-- ============================================================================

create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

comment on function touch_updated_at is
  'BEFORE UPDATE trigger: maintains updated_at without trusting the client.';

-- ============================================================================
--  SECTION 3 · ORGANISATION TREE
--
--  A single adjacency-list table models the whole structure:
--
--    program  "Teknik Robotika & Kecerdasan Buatan"   (root)
--      ├── class     "TRKB-1 25"   class_number=1, entry_year=2025
--      ├── class     "TRKB-2 25"   class_number=2, entry_year=2025
--      ├── class     "TRKB-1 24"   class_number=1, entry_year=2024
--      ├── division  "Divisi Riset & Teknologi"
--      ├── division  "Divisi Humas"
--      └── committee "Panitia Robotic Day 2026"       (temporary, has end_date)
--
--  Why one table instead of separate classes/divisions tables: permissions are
--  resolved by walking ancestors. With one table that is a single recursive CTE
--  reused by every policy. With several tables it becomes a union that must be
--  edited every time the Super Admin invents a new kind of unit.
-- ============================================================================

create table org_units (
  id              uuid primary key default gen_random_uuid(),
  type            org_unit_type not null,
  parent_id       uuid references org_units(id) on delete restrict,

  -- Human-facing identifier. For classes this is the campus format the students
  -- actually say out loud: 'TRKB-1 25' = TRKB, kelas 1, angkatan 2025.
  code            text not null,
  name            text not null,
  short_name      text,
  description     text,

  -- Class-only attributes. Enforced by the check constraint below.
  class_number    smallint,
  entry_year      smallint,

  -- Presentation
  icon            text,
  accent_color    text,
  sort_order      smallint not null default 0,

  is_active       boolean not null default true,
  -- Committees and other temporary units expire; classes and divisions do not.
  active_from     date,
  active_until    date,

  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint org_units_code_unique unique (code),

  -- Only a program may be a root; everything else must hang off something.
  constraint org_units_root_is_program
    check ((parent_id is null) = (type = 'program')),

  -- Class identity fields belong to classes and only to classes.
  constraint org_units_class_fields
    check (
      case when type = 'class'
        then class_number is not null and entry_year is not null
        else class_number is null and entry_year is null
      end
    ),

  constraint org_units_entry_year_sane
    check (entry_year is null or entry_year between 2000 and 2100),

  constraint org_units_active_window
    check (active_until is null or active_from is null or active_until >= active_from)
);

create index org_units_parent_idx       on org_units (parent_id);
create index org_units_type_active_idx  on org_units (type, is_active);
create index org_units_class_idx        on org_units (entry_year desc, class_number)
  where type = 'class';
create index org_units_name_trgm_idx    on org_units using gin (name gin_trgm_ops);

create trigger org_units_touch before update on org_units
  for each row execute function touch_updated_at();

comment on table org_units is
  'Adjacency-list tree of every organisational unit. Super Admin may add or '
  'remove divisions and committees freely; permission resolution walks parents.';
comment on column org_units.code is
  'Campus-facing code. Classes use the format ''TRKB-<kelas> <yy>'', e.g. ''TRKB-1 25''.';

-- Materialised ancestor lookup. Policies call this constantly, so it is marked
-- STABLE and the result is small enough for Postgres to cache per statement.
create or replace function org_unit_ancestors(p_unit uuid)
returns table (id uuid, depth int)
language sql stable as $$
  with recursive up as (
    select o.id, o.parent_id, 0 as depth
      from org_units o where o.id = p_unit
    union all
    select o.id, o.parent_id, up.depth + 1
      from org_units o join up on o.id = up.parent_id
  )
  select up.id, up.depth from up;
$$;

comment on function org_unit_ancestors is
  'The unit itself plus every ancestor, nearest first. Used by permission checks '
  'so that a program-level role implicitly covers all classes beneath it.';

create or replace function org_unit_descendants(p_unit uuid)
returns table (id uuid, depth int)
language sql stable as $$
  with recursive down as (
    select o.id, 0 as depth
      from org_units o where o.id = p_unit
    union all
    select o.id, down.depth + 1
      from org_units o join down on o.parent_id = down.id
  )
  select down.id, down.depth from down;
$$;

-- ============================================================================
--  SECTION 4 · ROLES
--
--  Roles are DATA, not an enum. The Super Admin can create 'Kadiv Media' next
--  periode without a migration. Permissions are a text[] of stable keys checked
--  by has_perm() in policies.sql; the canonical list is in
--  docs/04-roles-and-permissions.md.
-- ============================================================================

create table roles (
  id            uuid primary key default gen_random_uuid(),
  key           text not null unique,     -- 'ketua_kelas', machine-stable
  name_id       text not null,            -- 'Ketua Kelas'       (Bahasa Indonesia)
  name_en       text not null,            -- 'Class President'   (English toggle)
  description   text,

  scope         role_scope not null,
  -- Lower rank = more authority. Used for display order and for the rule that
  -- you may not assign or revoke a role at or above your own rank.
  rank          smallint not null,

  permissions   text[] not null default '{}',

  -- Most units allow exactly one holder of a leadership role at a time.
  is_singleton  boolean not null default false,
  -- System roles cannot be deleted or have their key changed, only renamed.
  is_system     boolean not null default false,

  icon          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint roles_rank_positive check (rank > 0),
  constraint roles_key_format check (key ~ '^[a-z][a-z0-9_]{1,48}$')
);

create index roles_scope_rank_idx on roles (scope, rank);

create trigger roles_touch before update on roles
  for each row execute function touch_updated_at();

comment on table roles is
  'Role definitions, editable by Super Admin. permissions[] holds stable keys; '
  'see docs/04-roles-and-permissions.md for the authoritative matrix.';

-- ============================================================================
--  SECTION 5 · IDENTITY & PROFILES
--
--  profiles.id is the same uuid as auth.users.id. Supabase owns credentials;
--  this table owns everything the program cares about.
-- ============================================================================

create table profiles (
  id                uuid primary key references auth.users(id) on delete cascade,

  -- Identity
  nim               text unique,
  full_name         text not null,
  display_name      text,
  pronouns          text,           -- free text; students fill their own
  email             text not null,

  -- Personalisation (feature 4)
  avatar_url        text,
  banner_url        text,
  headline          text,           -- one line under the name
  bio               text,
  links             jsonb not null default '[]'::jsonb,  -- [{label,url}]

  -- Per-person theming, stored server-side so it follows across devices
  accent            accent_seed not null default 'green',
  theme_mode        theme_mode  not null default 'system',
  locale            text not null default 'id',
  reduce_motion     boolean not null default false,

  -- Academic placement. primary_class_id is denormalised from memberships for
  -- fast dashboard queries; kept in sync by a trigger.
  entry_year        smallint,
  primary_class_id  uuid references org_units(id) on delete set null,

  status            user_status not null default 'pending',
  is_super_admin    boolean not null default false,

  last_seen_at      timestamptz,
  onboarded_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- NIM format is campus-defined; keep the check loose but non-empty.
  constraint profiles_nim_format check (nim is null or nim ~ '^[A-Za-z0-9.\-]{5,20}$'),
  constraint profiles_bio_length check (bio is null or length(bio) <= 500),
  constraint profiles_headline_length check (headline is null or length(headline) <= 100),
  constraint profiles_links_is_array check (jsonb_typeof(links) = 'array'),
  constraint profiles_locale check (locale in ('id', 'en'))
);

create index profiles_class_idx    on profiles (primary_class_id) where status = 'active';
create index profiles_status_idx   on profiles (status);
create index profiles_name_trgm    on profiles using gin (full_name gin_trgm_ops);
create unique index profiles_nim_lower_idx on profiles (lower(nim)) where nim is not null;

create trigger profiles_touch before update on profiles
  for each row execute function touch_updated_at();

comment on column profiles.pronouns is
  'Self-declared, free text. Never inferred from the name and never required.';
comment on column profiles.primary_class_id is
  'Denormalised from the primary active membership. Maintained by '
  'sync_primary_class(); do not write directly.';

-- ============================================================================
--  SECTION 6 · MEMBERSHIPS  (who holds which role, where, when)
--
--  This table is the heart of the permission system. A row says:
--  "<user> holds <role> in <org_unit> from <period_start> until <period_end>."
--
--  Handover between kepengurusan is therefore just setting period_end on the
--  old row and inserting a new one — no password sharing, and the history of
--  who led what is preserved permanently.
-- ============================================================================

create table memberships (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references profiles(id) on delete cascade,
  org_unit_id    uuid not null references org_units(id) on delete cascade,
  role_id        uuid not null references roles(id)     on delete restrict,

  status         membership_status not null default 'pending',
  -- A student's class membership is primary; HIMA and division roles are extra.
  is_primary     boolean not null default false,

  period_start   date not null default current_date,
  period_end     date,                  -- null = currently open

  -- Registration approval trail (feature: Ketua Kelas approves new members)
  requested_at   timestamptz not null default now(),
  requested_note text,
  decided_by     uuid references profiles(id) on delete set null,
  decided_at     timestamptz,
  decision_note  text,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint memberships_period_sane
    check (period_end is null or period_end >= period_start),

  -- One person cannot hold the same role in the same unit twice concurrently.
  constraint memberships_no_duplicate_open
    unique (user_id, org_unit_id, role_id, period_start),

  constraint memberships_decision_complete
    check (
      (status in ('pending'))
      or (status = 'rejected' and decided_by is not null)
      or (status in ('active', 'ended'))
    )
);

create index memberships_user_active_idx on memberships (user_id)
  where status = 'active';
create index memberships_unit_active_idx on memberships (org_unit_id, role_id)
  where status = 'active';
create index memberships_pending_idx on memberships (org_unit_id, requested_at)
  where status = 'pending';

-- Exactly one primary active membership per user.
create unique index memberships_one_primary_idx on memberships (user_id)
  where is_primary and status = 'active';

-- Singleton roles (Ketua HIMA, Ketua Kelas, …) may have only one open holder
-- per unit. Enforced with a partial unique index on the open-ended rows plus a
-- trigger for the closed-range case.
create unique index memberships_singleton_open_idx
  on memberships (org_unit_id, role_id)
  where status = 'active' and period_end is null;

create trigger memberships_touch before update on memberships
  for each row execute function touch_updated_at();

comment on table memberships is
  'Scoped, time-bounded role grants. Kepengurusan handover = close the old row '
  'and open a new one. Never delete: the history is the institutional memory.';

-- Keep profiles.primary_class_id in step with the primary membership.
create or replace function sync_primary_class()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
begin
  update profiles p
     set primary_class_id = (
           select m.org_unit_id
             from memberships m
             join org_units o on o.id = m.org_unit_id
            where m.user_id = v_user
              and m.status = 'active'
              and m.is_primary
              and o.type = 'class'
            limit 1
         )
   where p.id = v_user;
  return null;
end $$;

create trigger memberships_sync_primary_class
  after insert or update or delete on memberships
  for each row execute function sync_primary_class();

-- Reject a singleton role being granted to a second person over an overlapping
-- closed period (the partial unique index only covers open-ended rows).
create or replace function check_singleton_role()
returns trigger language plpgsql as $$
declare
  v_singleton boolean;
  v_clash     int;
begin
  select is_singleton into v_singleton from roles where id = new.role_id;
  if not coalesce(v_singleton, false) or new.status <> 'active' then
    return new;
  end if;

  select count(*) into v_clash
    from memberships m
   where m.org_unit_id = new.org_unit_id
     and m.role_id     = new.role_id
     and m.status      = 'active'
     and m.id         <> new.id
     and daterange(m.period_start, m.period_end, '[]')
         && daterange(new.period_start, new.period_end, '[]');

  if v_clash > 0 then
    raise exception
      'Peran ini hanya boleh dipegang satu orang pada satu waktu di unit tersebut.'
      using errcode = 'unique_violation';
  end if;
  return new;
end $$;

create trigger memberships_singleton_guard
  before insert or update on memberships
  for each row execute function check_singleton_role();

-- ============================================================================
--  SECTION 7 · ACADEMIC CALENDAR
--
--  Classes are stored by ANGKATAN (entry year), never by semester number.
--  The semester a class is currently in is DERIVED from the active term, so
--  nobody has to run a "promote everyone" job twice a year — and a student who
--  repeats a subject does not break the model.
--
--  Term ordinal arithmetic:
--    ordinal = year_start * 2 + (kind = 'genap')
--    semester_of(entry_year, term) = term.ordinal - (entry_year * 2) + 1
--
--  So angkatan 2025 in ganjil 2025/2026 (ordinal 4050) is semester 1;
--  in genap 2025/2026 (ordinal 4051) it is semester 2. Correct, automatically.
-- ============================================================================

create table academic_terms (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,         -- '2025/2026-1'
  name          text not null,                -- 'Semester Ganjil 2025/2026'
  kind          academic_term_kind not null,
  year_start    smallint not null,            -- 2025 for 2025/2026

  start_date    date not null,
  end_date      date not null,
  -- Teaching weeks; schedule_rules reference weeks within this range.
  week_count    smallint not null default 16,

  -- Non-teaching ranges (UTS, UAS, libur) excluded from session generation.
  breaks        jsonb not null default '[]'::jsonb,  -- [{from,to,label}]

  is_current    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint academic_terms_dates check (end_date > start_date),
  constraint academic_terms_weeks check (week_count between 1 and 30),
  constraint academic_terms_breaks_array check (jsonb_typeof(breaks) = 'array'),

  -- Derived ordinal, generated so it can be indexed and joined on.
  ordinal       int generated always as
                (year_start * 2 + case when kind = 'genap' then 1 else 0 end) stored
);

-- Only one current term at a time; the app relies on this everywhere.
create unique index academic_terms_one_current_idx on academic_terms (is_current)
  where is_current;
create index academic_terms_ordinal_idx on academic_terms (ordinal desc);

create trigger academic_terms_touch before update on academic_terms
  for each row execute function touch_updated_at();

create or replace function current_term()
returns academic_terms language sql stable as $$
  select * from academic_terms where is_current limit 1;
$$;

create or replace function semester_of(p_entry_year smallint, p_term_id uuid default null)
returns smallint language sql stable as $$
  select greatest(1, (t.ordinal - (p_entry_year * 2) + 1))::smallint
    from academic_terms t
   where t.id = coalesce(p_term_id, (select id from academic_terms where is_current limit 1));
$$;

comment on function semester_of is
  'Semester number a given angkatan is currently in. Derived, never stored, so '
  'the whole program advances a semester the moment a new term is marked current.';

-- Convenience view: every class with its live semester label.
create view class_overview as
  select o.id,
         o.code,
         o.name,
         o.class_number,
         o.entry_year,
         semester_of(o.entry_year)                      as semester,
         'Semester ' || semester_of(o.entry_year)::text  as semester_label,
         o.is_active,
         (select count(*) from memberships m
           where m.org_unit_id = o.id and m.status = 'active')      as member_count,
         (select count(*) from memberships m
           where m.org_unit_id = o.id and m.status = 'pending')     as pending_count
    from org_units o
   where o.type = 'class';

-- ============================================================================
--  SECTION 8 · SUBJECTS & LECTURERS
--
--  Dosen are DATA, not accounts (see docs/01). A lecturer row exists so a task
--  can say who assigned it and a schedule can say who teaches it. No login,
--  therefore no adoption dependency on any lecturer.
-- ============================================================================

create table lecturers (
  id           uuid primary key default gen_random_uuid(),
  code         text unique,              -- campus lecturer code, if known
  full_name    text not null,
  title_prefix text,                     -- 'Dr.', 'Ir.'
  title_suffix text,                     -- 'S.T., M.T.'
  email        text,
  phone        text,
  office       text,
  photo_url    text,
  notes        text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index lecturers_name_trgm on lecturers using gin (full_name gin_trgm_ops);

create trigger lecturers_touch before update on lecturers
  for each row execute function touch_updated_at();

-- Display name with titles, so the UI never has to concatenate.
create or replace function lecturer_display(p_lecturer lecturers)
returns text language sql immutable as $$
  select trim(
    coalesce(p_lecturer.title_prefix || ' ', '') ||
    p_lecturer.full_name ||
    coalesce(', ' || p_lecturer.title_suffix, '')
  );
$$;

create table subjects (
  id            uuid primary key default gen_random_uuid(),
  program_id    uuid not null references org_units(id) on delete cascade,
  code          text not null,            -- 'TRKB-304'
  name          text not null,            -- 'Sistem Kendali Cerdas'
  short_name    text,
  sks           smallint,                 -- credit units
  -- Which semester this subject normally belongs to; used to pre-filter the
  -- subject picker when a sekretaris inputs the jadwal.
  default_semester smallint,
  description   text,
  color         text,                     -- per-subject accent in the timetable
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint subjects_code_unique_per_program unique (program_id, code),
  constraint subjects_sks_sane check (sks is null or sks between 1 and 12),
  constraint subjects_semester_sane
    check (default_semester is null or default_semester between 1 and 14)
);

create index subjects_program_idx on subjects (program_id, is_active);
create index subjects_name_trgm on subjects using gin (name gin_trgm_ops);

create trigger subjects_touch before update on subjects
  for each row execute function touch_updated_at();

-- ============================================================================
--  SECTION 9 · SCHEDULE  (feature 1)
--
--  Two-level model, and the reason matters:
--
--    schedule_rules    — the INTENT. "Sistem Kendali Cerdas, Senin 07:00–09:30,
--                        Lab Robotika 2, weeks 1–16." One row per subject slot.
--                        This is what the sekretaris types or imports.
--
--    schedule_sessions — the OCCURRENCES, generated from the rules. One row per
--                        actual meeting on an actual date.
--
--  A single-table design cannot express "class on 14 Oct moved to Lab 3" or
--  "cancelled, dosen sakit" without corrupting the recurring definition.
--  Generating occurrences also makes reminders, attendance (v2) and "what do I
--  have today" plain indexed queries instead of recurrence maths at read time.
-- ============================================================================

-- Normalises a (start_time, end_time) pair into a comparable range on a fixed
-- reference date. Defined BEFORE schedule_rules because that table's exclusion
-- constraint calls it, and Postgres resolves constraint expressions at DDL time.
-- IMMUTABLE is required for use in an index expression.
create or replace function timerange_from_times(p_start time, p_end time)
returns tsrange language sql immutable as $$
  select tsrange(
    ('2000-01-01'::date + p_start)::timestamp,
    ('2000-01-01'::date + p_end)::timestamp,
    '[)'
  );
$$;

create table schedule_rules (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references org_units(id) on delete cascade,
  term_id       uuid not null references academic_terms(id) on delete cascade,
  subject_id    uuid not null references subjects(id)  on delete restrict,
  lecturer_id   uuid references lecturers(id) on delete set null,

  kind          schedule_kind not null default 'teori',

  -- ISO-8601 day of week: 1 = Monday … 7 = Sunday.
  day_of_week   smallint not null,
  start_time    time not null,
  end_time      time not null,
  room          text,

  -- Teaching-week window inside the term, so a subject that only runs in the
  -- second half of the semester is expressible.
  week_from     smallint not null default 1,
  week_to       smallint,                 -- null = until end of term

  note          text,
  is_active     boolean not null default true,

  created_by    uuid references profiles(id) on delete set null,
  updated_by    uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint schedule_rules_dow     check (day_of_week between 1 and 7),
  constraint schedule_rules_times   check (end_time > start_time),
  constraint schedule_rules_weeks   check (week_to is null or week_to >= week_from),

  -- Clash detection: the same class cannot have two active slots overlapping on
  -- the same weekday. Uses an exclusion constraint so the DATABASE refuses the
  -- bad row — a typo during jadwal entry is caught at insert, not by a reviewer.
  constraint schedule_rules_no_class_clash
    exclude using gist (
      class_id    with =,
      day_of_week with =,
      (timerange_from_times(start_time, end_time)) with &&
    ) where (is_active)
);

create index schedule_rules_class_term_idx on schedule_rules (class_id, term_id)
  where is_active;
create index schedule_rules_dow_idx on schedule_rules (term_id, day_of_week, start_time);

create trigger schedule_rules_touch before update on schedule_rules
  for each row execute function touch_updated_at();

comment on table schedule_rules is
  'Recurring intent, entered once per semester by the sekretaris (manually or '
  'via CSV import). Occurrences are generated into schedule_sessions.';

create table schedule_sessions (
  id            uuid primary key default gen_random_uuid(),
  rule_id       uuid references schedule_rules(id) on delete cascade,
  class_id      uuid not null references org_units(id) on delete cascade,
  term_id       uuid not null references academic_terms(id) on delete cascade,
  subject_id    uuid not null references subjects(id) on delete restrict,
  lecturer_id   uuid references lecturers(id) on delete set null,

  kind          schedule_kind not null default 'teori',
  week_number   smallint,
  session_date  date not null,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  room          text,

  status        session_status not null default 'scheduled',
  -- Set when a sekretaris edits one occurrence; protects it from being
  -- overwritten the next time sessions are regenerated from the rule.
  is_override   boolean not null default false,
  status_note   text,                     -- 'Dosen sakit', 'Pindah ke Lab 3'
  moved_from    timestamptz,              -- original slot, when status='moved'

  updated_by    uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint schedule_sessions_times check (ends_at > starts_at),
  -- One occurrence of a rule per date, so regeneration is idempotent.
  constraint schedule_sessions_unique_occurrence unique (rule_id, session_date)
);

create index schedule_sessions_class_date_idx
  on schedule_sessions (class_id, session_date)
  where status <> 'cancelled';
create index schedule_sessions_upcoming_idx
  on schedule_sessions (starts_at)
  where status in ('scheduled', 'moved');
create index schedule_sessions_term_idx on schedule_sessions (term_id, class_id);

create trigger schedule_sessions_touch before update on schedule_sessions
  for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
--  Session generation. Idempotent: safe to run repeatedly, never clobbers an
--  occurrence a human has overridden, and skips the term's break ranges.
-- ---------------------------------------------------------------------------
create or replace function generate_sessions_for_rule(p_rule_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  r             schedule_rules;
  t             academic_terms;
  v_week        smallint;
  v_date        date;
  v_first       date;
  v_inserted    int := 0;
  v_in_break    boolean;
  brk           jsonb;
begin
  select * into r from schedule_rules where id = p_rule_id and is_active;
  if not found then return 0; end if;
  select * into t from academic_terms where id = r.term_id;

  -- Week 1 starts on the term's first ISO week; align to the rule's weekday.
  v_first := t.start_date
             + ((r.day_of_week - extract(isodow from t.start_date)::int + 7) % 7);

  for v_week in r.week_from .. coalesce(r.week_to, t.week_count) loop
    v_date := v_first + ((v_week - r.week_from) * 7);
    exit when v_date > t.end_date;

    -- Skip UTS/UAS/libur windows declared on the term.
    v_in_break := false;
    for brk in select * from jsonb_array_elements(t.breaks) loop
      if v_date between (brk->>'from')::date and (brk->>'to')::date then
        v_in_break := true;
        exit;
      end if;
    end loop;
    continue when v_in_break;

    insert into schedule_sessions (
      rule_id, class_id, term_id, subject_id, lecturer_id, kind,
      week_number, session_date, starts_at, ends_at, room
    ) values (
      r.id, r.class_id, r.term_id, r.subject_id, r.lecturer_id, r.kind,
      v_week, v_date,
      (v_date + r.start_time) at time zone 'Asia/Jakarta',
      (v_date + r.end_time)   at time zone 'Asia/Jakarta',
      r.room
    )
    on conflict (rule_id, session_date) do update
       set subject_id  = excluded.subject_id,
           lecturer_id = excluded.lecturer_id,
           kind        = excluded.kind,
           starts_at   = excluded.starts_at,
           ends_at     = excluded.ends_at,
           room        = excluded.room,
           updated_at  = now()
     -- The crucial guard: never overwrite a human's per-session edit.
     where schedule_sessions.is_override = false;

    v_inserted := v_inserted + 1;
  end loop;

  return v_inserted;
end $$;

comment on function generate_sessions_for_rule is
  'Expands one recurring rule into dated occurrences. Idempotent, break-aware, '
  'and never overwrites a session a human marked is_override.';

create or replace function generate_sessions_for_term(p_term_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_rule uuid; v_total int := 0;
begin
  for v_rule in
    select id from schedule_rules where term_id = p_term_id and is_active
  loop
    v_total := v_total + generate_sessions_for_rule(v_rule);
  end loop;
  return v_total;
end $$;

-- Regenerate automatically whenever a rule is created or its timing changes.
create or replace function schedule_rules_regenerate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform generate_sessions_for_rule(new.id);
  return null;
end $$;

create trigger schedule_rules_after_write
  after insert or update of day_of_week, start_time, end_time, room,
                            week_from, week_to, subject_id, lecturer_id, is_active
  on schedule_rules
  for each row execute function schedule_rules_regenerate();

-- ============================================================================
--  SECTION 10 · TASKS  (feature 3)
--
--  Created by Ketua/Sekretaris Kelas from what the dosen announced in class.
--  Shared definition in `tasks`; each student's own progress in
--  `task_submissions`. Keeping those apart means one student ticking "done"
--  cannot possibly change what anyone else sees.
-- ============================================================================

create table tasks (
  id             uuid primary key default gen_random_uuid(),
  class_id       uuid not null references org_units(id) on delete cascade,
  term_id        uuid references academic_terms(id) on delete set null,
  subject_id     uuid references subjects(id)  on delete set null,
  lecturer_id    uuid references lecturers(id) on delete set null,
  -- Optional link to the meeting it was announced in, for context.
  session_id     uuid references schedule_sessions(id) on delete set null,

  title          text not null,
  description    text,
  kind           task_kind not null default 'tugas',
  priority       task_priority not null default 'normal',

  assigned_at    timestamptz not null default now(),
  due_at         timestamptz not null,

  -- How it is handed in: 'LMS UNIKOM', 'Kumpulkan di kelas', 'Email dosen'…
  submit_channel text,
  link_url       text,
  attachments    jsonb not null default '[]'::jsonb,   -- [{name,path,size,mime}]

  -- Draft tasks do not notify anyone. A sekretaris can prepare at 02:00
  -- without waking 40 people up.
  is_published   boolean not null default true,
  published_at   timestamptz,

  created_by     uuid references profiles(id) on delete set null,
  updated_by     uuid references profiles(id) on delete set null,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint tasks_title_length check (length(btrim(title)) between 3 and 160),
  constraint tasks_due_after_assigned check (due_at > assigned_at - interval '1 day'),
  constraint tasks_attachments_array check (jsonb_typeof(attachments) = 'array'),
  constraint tasks_url_shape check (link_url is null or link_url ~* '^https?://')
);

create index tasks_class_due_idx on tasks (class_id, due_at)
  where deleted_at is null and is_published;
create index tasks_due_soon_idx on tasks (due_at)
  where deleted_at is null and is_published;
create index tasks_subject_idx on tasks (subject_id) where deleted_at is null;
create index tasks_title_trgm on tasks using gin (title gin_trgm_ops);

create trigger tasks_touch before update on tasks
  for each row execute function touch_updated_at();

create table task_submissions (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references tasks(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,

  state         submission_state not null default 'todo',
  submitted_at  timestamptz,
  note          text,                    -- private to the student
  -- Set when the student marks done after due_at; drives the on-time stats.
  was_late      boolean not null default false,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint task_submissions_unique unique (task_id, user_id)
);

create index task_submissions_user_state_idx on task_submissions (user_id, state);

create trigger task_submissions_touch before update on task_submissions
  for each row execute function touch_updated_at();

-- Stamp lateness and submitted_at from the server clock, not the client's.
create or replace function stamp_submission()
returns trigger language plpgsql as $$
declare v_due timestamptz;
begin
  if new.state in ('submitted', 'done')
     and (old.state is null or old.state not in ('submitted', 'done')) then
    select due_at into v_due from tasks where id = new.task_id;
    new.submitted_at := now();
    new.was_late     := now() > v_due;
  end if;
  return new;
end $$;

create trigger task_submissions_stamp
  before insert or update of state on task_submissions
  for each row execute function stamp_submission();

-- ============================================================================
--  SECTION 11 · NOTIFICATIONS  (feature 3, the reminder half)
--
--  Three tables with three different jobs, and the split is deliberate:
--
--    notification_preferences — what each person wants, per channel
--    notification_jobs        — the OUTBOX. One row per (person, event, channel)
--                               with a dedupe_key, so a cron re-run or a crash
--                               mid-send can never double-notify anyone.
--    notifications            — the in-app inbox (the bell icon)
--
--  The outbox pattern is the whole reason this is reliable. Enqueueing is a
--  pure SQL transaction; delivery is a separate drain step that may fail and
--  retry without ever losing or duplicating a reminder.
-- ============================================================================

-- Range check over an int[], as an IMMUTABLE function so it can be used inside a
-- CHECK constraint (which forbids subqueries and set-returning functions).
create or replace function int_array_all_between(p_arr int[], p_min int, p_max int)
returns boolean language sql immutable as $$
  select coalesce(bool_and(v between p_min and p_max), true)
    from unnest(coalesce(p_arr, '{}'::int[])) as v;
$$;

create table notification_preferences (
  user_id            uuid primary key references profiles(id) on delete cascade,

  -- Channel switches
  inapp_enabled      boolean not null default true,
  push_enabled       boolean not null default true,
  email_enabled      boolean not null default true,

  -- Reminder offsets in MINUTES BEFORE the event. Defaults encode the brief:
  -- H-1 (1440 min) plus a 3-hour final warning.
  task_offsets       int[] not null default array[1440, 180],
  -- Class reminders are short-range by nature.
  class_offsets      int[] not null default array[30],

  -- H-1 reminders are sent at this local hour rather than exactly 24h before,
  -- because a 03:00 ping for a 03:00-deadline-tomorrow is useless.
  daily_digest_hour  smallint not null default 18,
  digest_enabled     boolean not null default true,

  -- Quiet hours in Asia/Jakarta. Jobs landing inside are deferred, never
  -- dropped — a suppressed reminder is a missed deadline.
  quiet_start        time,
  quiet_end          time,

  -- Mute specific subjects or whole classes without muting everything.
  muted_subject_ids  uuid[] not null default '{}',
  muted_class_ids    uuid[] not null default '{}',
  chat_mentions_only boolean not null default false,

  timezone           text not null default 'Asia/Jakarta',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint notif_prefs_digest_hour check (daily_digest_hour between 0 and 23),
  constraint notif_prefs_task_offsets
    check (array_length(task_offsets, 1) between 1 and 5),
  -- Offsets must be sane: at least 5 minutes, at most 14 days (20160 min).
  -- Uses a helper function because a CHECK constraint may not contain a subquery
  -- and may not call a set-returning function such as unnest().
  constraint notif_prefs_task_offsets_range
    check (int_array_all_between(task_offsets, 5, 20160)),
  constraint notif_prefs_class_offsets_range
    check (int_array_all_between(class_offsets, 5, 1440))
);

create trigger notification_preferences_touch before update on notification_preferences
  for each row execute function touch_updated_at();

comment on column notification_preferences.quiet_start is
  'Quiet hours DEFER delivery to quiet_end; they never cancel it. Silently '
  'dropping a deadline reminder would defeat the purpose of the product.';

-- Give every new profile a preferences row, so the reminder engine never has
-- to handle a missing-row case.
create or replace function ensure_notification_preferences()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into notification_preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return null;
end $$;

create trigger profiles_create_notif_prefs
  after insert on profiles
  for each row execute function ensure_notification_preferences();

create table push_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  endpoint     text not null unique,
  p256dh       text not null,
  auth         text not null,
  user_agent   text,
  platform     text,
  -- Cleared when the push service returns 404/410; a stale endpoint is dead.
  failed_count smallint not null default 0,
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

create index push_subscriptions_user_idx on push_subscriptions (user_id);

create table notification_jobs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  channel       notification_channel not null,

  -- Polymorphic source. Kept loose so new reminder types ('vote closing',
  -- 'proker deadline') need no schema change.
  source_type   text not null,            -- 'task' | 'session' | 'announcement' | 'chat'
  source_id     uuid,

  title         text not null,
  body          text,
  deep_link     text,                     -- '/tugas/<id>'
  payload       jsonb not null default '{}'::jsonb,

  scheduled_at  timestamptz not null,
  state         job_state not null default 'queued',
  attempts      smallint not null default 0,
  sent_at       timestamptz,
  last_error    text,

  -- THE anti-duplicate guarantee: one row per person per event per offset per
  -- channel, forever. Re-running the enqueuer is a no-op.
  dedupe_key    text not null unique,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- The drain query: cheap, index-only, ordered.
create index notification_jobs_due_idx on notification_jobs (scheduled_at)
  where state = 'queued';
create index notification_jobs_user_idx on notification_jobs (user_id, created_at desc);
create index notification_jobs_source_idx on notification_jobs (source_type, source_id);

create trigger notification_jobs_touch before update on notification_jobs
  for each row execute function touch_updated_at();

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  kind        text not null,              -- 'task_due' | 'approval_needed' | …
  title       text not null,
  body        text,
  deep_link   text,
  icon        text,
  payload     jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_inbox_idx on notifications (user_id, created_at desc);
create index notifications_unread_idx on notifications (user_id)
  where read_at is null;

-- ---------------------------------------------------------------------------
--  Enqueue reminders for one task, honouring every member's own preferences.
--  Called by a trigger when a task is published or its due_at changes.
-- ---------------------------------------------------------------------------
create or replace function enqueue_task_reminders(p_task_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  t          tasks;
  v_subject  text;
  v_member   record;
  v_offset   int;
  v_when     timestamptz;
  v_channel  notification_channel;
  v_count    int := 0;
  -- MUST be `timestamp` (naive), not `timestamptz`. `due_at at time zone tz`
  -- produces a naive local timestamp; storing it in a timestamptz variable makes
  -- Postgres reinterpret it in the server timezone, and the `at time zone` below
  -- then converts a second time. That bug sent every H-1 reminder at 08:00 WIB
  -- instead of 18:00. Caught by db/tests/03-notifications.sql.
  v_local    timestamp;
begin
  select * into t from tasks where id = p_task_id;
  if not found or t.deleted_at is not null or not t.is_published then
    return 0;
  end if;

  select coalesce(s.name, 'Tugas') into v_subject
    from subjects s where s.id = t.subject_id;

  -- Revoke anything still queued for this task; due_at may have moved.
  update notification_jobs
     set state = 'cancelled', updated_at = now()
   where source_type = 'task' and source_id = p_task_id and state = 'queued';

  for v_member in
    select m.user_id, np.*
      from memberships m
      join profiles p  on p.id = m.user_id and p.status = 'active'
      join notification_preferences np on np.user_id = m.user_id
     where m.org_unit_id = t.class_id
       and m.status = 'active'
  loop
    -- Respect per-subject and per-class mutes.
    continue when t.subject_id = any (v_member.muted_subject_ids);
    continue when t.class_id   = any (v_member.muted_class_ids);

    foreach v_offset in array v_member.task_offsets loop
      v_when := t.due_at - make_interval(mins => v_offset);

      -- The H-1 case: fire at the person's digest hour the day before rather
      -- than at an arbitrary middle-of-the-night moment.
      if v_offset >= 1440 then
        v_local := date_trunc('day', (t.due_at at time zone v_member.timezone))
                   - make_interval(days => v_offset / 1440)
                   + make_interval(hours => v_member.daily_digest_hour);
        v_when := v_local at time zone v_member.timezone;
      end if;

      -- Never enqueue something already in the past.
      continue when v_when <= now();

      -- Defer out of quiet hours instead of dropping.
      v_when := shift_out_of_quiet_hours(
                  v_when, v_member.quiet_start, v_member.quiet_end, v_member.timezone);

      foreach v_channel in array array['inapp','push','email']::notification_channel[] loop
        continue when v_channel = 'inapp' and not v_member.inapp_enabled;
        continue when v_channel = 'push'  and not v_member.push_enabled;
        -- Email is digest-only by default (free-tier send limits, see docs/02).
        continue when v_channel = 'email' and (not v_member.email_enabled or v_offset < 1440);

        insert into notification_jobs (
          user_id, channel, source_type, source_id,
          title, body, deep_link, scheduled_at, payload, dedupe_key
        ) values (
          v_member.user_id, v_channel, 'task', t.id,
          case when v_offset >= 1440
               then 'Besok: ' || t.title
               else 'Segera: ' || t.title end,
          v_subject || ' · dikumpulkan ' ||
            to_char(t.due_at at time zone v_member.timezone, 'DD Mon YYYY HH24:MI'),
          '/tugas/' || t.id::text,
          v_when,
          jsonb_build_object('offset_minutes', v_offset, 'kind', t.kind, 'priority', t.priority),
          concat_ws(':', 'task', t.id::text, v_member.user_id::text,
                         v_offset::text, v_channel::text)
        )
        on conflict (dedupe_key) do update
           set scheduled_at = excluded.scheduled_at,
               title        = excluded.title,
               body         = excluded.body,
               state        = 'queued',
               updated_at   = now()
         where notification_jobs.state in ('queued', 'cancelled');

        v_count := v_count + 1;
      end loop;
    end loop;
  end loop;

  return v_count;
end $$;

comment on function enqueue_task_reminders is
  'Materialises per-member reminder jobs for a task. Idempotent via dedupe_key; '
  're-runs after a due-date change simply reschedule the existing rows.';

create or replace function shift_out_of_quiet_hours(
  p_when timestamptz, p_start time, p_end time, p_tz text
) returns timestamptz language plpgsql immutable as $$
declare v_local timestamp; v_time time;
begin
  if p_start is null or p_end is null then return p_when; end if;
  v_local := p_when at time zone p_tz;
  v_time  := v_local::time;

  -- Window that does not cross midnight (e.g. 01:00–06:00)
  if p_start < p_end then
    if v_time >= p_start and v_time < p_end then
      return ((v_local::date + p_end) at time zone p_tz);
    end if;
  -- Window that crosses midnight (e.g. 22:00–06:00)
  else
    if v_time >= p_start then
      return (((v_local::date + 1) + p_end) at time zone p_tz);
    elsif v_time < p_end then
      return ((v_local::date + p_end) at time zone p_tz);
    end if;
  end if;
  return p_when;
end $$;

create or replace function tasks_after_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_published and new.deleted_at is null then
    perform enqueue_task_reminders(new.id);
  elsif new.deleted_at is not null then
    update notification_jobs
       set state = 'cancelled', updated_at = now()
     where source_type = 'task' and source_id = new.id and state = 'queued';
  end if;
  return null;
end $$;

create trigger tasks_enqueue_reminders
  after insert or update of due_at, is_published, title, deleted_at on tasks
  for each row execute function tasks_after_write();

-- ---------------------------------------------------------------------------
--  Class reminders ("kelas mulai 30 menit lagi"). Enqueued on a rolling
--  48-hour horizon by pg_cron rather than for the whole semester at once —
--  otherwise one term would create ~60,000 dead rows.
-- ---------------------------------------------------------------------------
create or replace function enqueue_upcoming_class_reminders(p_horizon interval default interval '48 hours')
returns int language plpgsql security definer set search_path = public as $$
declare
  v_row     record;
  v_offset  int;
  v_when    timestamptz;
  v_channel notification_channel;
  v_count   int := 0;
begin
  for v_row in
    select ss.id as session_id, ss.starts_at, ss.room, ss.class_id,
           s.name as subject_name, m.user_id, np.*
      from schedule_sessions ss
      join subjects s   on s.id = ss.subject_id
      join memberships m on m.org_unit_id = ss.class_id and m.status = 'active'
      join profiles p   on p.id = m.user_id and p.status = 'active'
      join notification_preferences np on np.user_id = m.user_id
     where ss.status in ('scheduled', 'moved')
       and ss.starts_at between now() and now() + p_horizon
  loop
    continue when v_row.class_id = any (v_row.muted_class_ids);

    foreach v_offset in array v_row.class_offsets loop
      v_when := v_row.starts_at - make_interval(mins => v_offset);
      continue when v_when <= now();

      -- One job per enabled channel. An earlier version picked a single channel
      -- with `case when push_enabled then 'push' else 'inapp' end`, which was
      -- both wrong behaviour (a student with push on got no bell entry) and a
      -- type error: an unquoted CASE yields text, not notification_channel.
      -- Email is deliberately absent — nobody emails you that class starts in
      -- 30 minutes.
      foreach v_channel in array array['inapp','push']::notification_channel[] loop
        continue when v_channel = 'inapp' and not v_row.inapp_enabled;
        continue when v_channel = 'push'  and not v_row.push_enabled;

        insert into notification_jobs (
          user_id, channel, source_type, source_id,
          title, body, deep_link, scheduled_at, dedupe_key
        ) values (
          v_row.user_id,
          v_channel,
          'session', v_row.session_id,
          v_row.subject_name || ' · ' || v_offset || ' menit lagi',
          coalesce('Ruang ' || v_row.room, 'Ruang belum ditentukan'),
          '/jadwal?s=' || v_row.session_id::text,
          v_when,
          concat_ws(':', 'session', v_row.session_id::text,
                         v_row.user_id::text, v_offset::text, v_channel::text)
        )
        on conflict (dedupe_key) do nothing;

        v_count := v_count + 1;
      end loop;
    end loop;
  end loop;

  return v_count;
end $$;

-- A cancelled or moved class must revoke its pending reminders.
create or replace function sessions_after_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('cancelled', 'moved') then
    update notification_jobs
       set state = 'cancelled', updated_at = now()
     where source_type = 'session' and source_id = new.id and state = 'queued';

    insert into notifications (user_id, kind, title, body, deep_link)
    select m.user_id,
           'session_' || new.status,
           case when new.status = 'cancelled'
                then 'Kelas dibatalkan'
                else 'Jadwal kelas berubah' end,
           coalesce(new.status_note, 'Cek jadwal untuk detail.'),
           '/jadwal?s=' || new.id::text
      from memberships m
     where m.org_unit_id = new.class_id and m.status = 'active';
  end if;
  return null;
end $$;

create trigger schedule_sessions_status_change
  after update of status on schedule_sessions
  for each row when (old.status is distinct from new.status)
  execute function sessions_after_status_change();

-- ============================================================================
--  SECTION 12 · CHAT  (feature 5)
--
--  Rooms are auto-provisioned for every class and division so there is never an
--  empty-state problem, plus opt-in public rooms and 1-to-1 DMs.
--
--  PRIVACY, STATED PLAINLY: messages are stored unencrypted. Super Admins can
--  read them in the database. The UI says so on the room list. v1 does not
--  pretend otherwise — see docs/06-chat.md.
-- ============================================================================

create table chat_rooms (
  id            uuid primary key default gen_random_uuid(),
  kind          room_kind not null,
  org_unit_id   uuid references org_units(id) on delete cascade,

  name          text,
  topic         text,
  icon          text,
  accent_color  text,

  -- Private rooms are invisible to non-members, including in search.
  is_private    boolean not null default false,
  -- Announcement channels: only members with post rights may write.
  is_readonly   boolean not null default false,

  -- Canonical identity for a DM: the two user ids sorted and joined, so
  -- opening a DM twice can never create a second thread.
  dm_key        text unique,

  last_message_at timestamptz,
  created_by    uuid references profiles(id) on delete set null,
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint chat_rooms_scope_matches_kind
    check (
      case kind
        when 'dm'     then org_unit_id is null and dm_key is not null
        when 'public' then dm_key is null
        else org_unit_id is not null and dm_key is null
      end
    ),
  constraint chat_rooms_named_unless_dm
    check (kind = 'dm' or name is not null)
);

create index chat_rooms_unit_idx on chat_rooms (org_unit_id, kind);
create index chat_rooms_recent_idx on chat_rooms (last_message_at desc nulls last);

create trigger chat_rooms_touch before update on chat_rooms
  for each row execute function touch_updated_at();

create table chat_members (
  room_id      uuid not null references chat_rooms(id) on delete cascade,
  user_id      uuid not null references profiles(id)   on delete cascade,
  role         room_member_role not null default 'member',
  joined_at    timestamptz not null default now(),
  last_read_at timestamptz,
  muted_until  timestamptz,
  is_pinned    boolean not null default false,
  primary key (room_id, user_id)
);

create index chat_members_user_idx on chat_members (user_id);

create table chat_messages (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references chat_rooms(id) on delete cascade,
  author_id    uuid references profiles(id) on delete set null,

  kind         message_kind not null default 'text',
  body         text,
  attachments  jsonb not null default '[]'::jsonb,  -- [{path,width,height,mime,size}]

  reply_to_id  uuid references chat_messages(id) on delete set null,
  mentions     uuid[] not null default '{}',

  edited_at    timestamptz,
  -- Soft delete: the row stays so replies and read state do not dangle, but
  -- body is blanked by the trigger below. "Deleted" must actually delete the
  -- content, not just hide it behind a UI flag.
  deleted_at   timestamptz,
  deleted_by   uuid references profiles(id) on delete set null,

  created_at   timestamptz not null default now(),

  constraint chat_messages_has_content
    check (deleted_at is not null or kind = 'system'
           or length(btrim(coalesce(body, ''))) > 0
           or jsonb_array_length(attachments) > 0),
  constraint chat_messages_body_length check (body is null or length(body) <= 4000),
  constraint chat_messages_attachments_array check (jsonb_typeof(attachments) = 'array')
);

create index chat_messages_room_time_idx on chat_messages (room_id, created_at desc);
create index chat_messages_author_idx on chat_messages (author_id, created_at desc);
create index chat_messages_mentions_idx on chat_messages using gin (mentions);
create index chat_messages_body_trgm on chat_messages using gin (body gin_trgm_ops)
  where deleted_at is null;

create table chat_reactions (
  message_id uuid not null references chat_messages(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji),
  constraint chat_reactions_emoji_short check (length(emoji) <= 16)
);

-- Blank the body on soft delete, so "hapus" removes the content for real.
create or replace function redact_deleted_message()
returns trigger language plpgsql as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    new.body := null;
    new.attachments := '[]'::jsonb;
    new.mentions := '{}';
  end if;
  return new;
end $$;

create trigger chat_messages_redact
  before update of deleted_at on chat_messages
  for each row execute function redact_deleted_message();

create or replace function bump_room_activity()
returns trigger language plpgsql as $$
begin
  update chat_rooms set last_message_at = new.created_at, updated_at = now()
   where id = new.room_id;
  return null;
end $$;

create trigger chat_messages_bump_room
  after insert on chat_messages
  for each row execute function bump_room_activity();

-- Deterministic DM key so a thread is created at most once per pair.
create or replace function dm_key_for(a uuid, b uuid)
returns text language sql immutable as $$
  select least(a::text, b::text) || '|' || greatest(a::text, b::text);
$$;

create or replace function open_dm(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_key text; v_room uuid;
begin
  if v_me is null or v_me = p_other then
    raise exception 'Tidak dapat membuka DM dengan diri sendiri.';
  end if;
  v_key := dm_key_for(v_me, p_other);

  select id into v_room from chat_rooms where dm_key = v_key;
  if v_room is null then
    insert into chat_rooms (kind, dm_key, is_private, created_by)
    values ('dm', v_key, true, v_me)
    returning id into v_room;

    insert into chat_members (room_id, user_id, role)
    values (v_room, v_me, 'member'), (v_room, p_other, 'member');
  end if;
  return v_room;
end $$;

-- Auto-provision a room whenever a class or division is created, and enrol
-- every approved member automatically.
create or replace function provision_unit_room()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.type in ('class', 'division', 'committee') then
    insert into chat_rooms (kind, org_unit_id, name, topic, is_private, created_by)
    values (
      case new.type when 'class' then 'class'::room_kind
                    when 'division' then 'division'::room_kind
                    else 'division'::room_kind end,
      new.id,
      new.name,
      'Ruang resmi ' || new.name,
      true,
      null
    )
    on conflict do nothing;
  end if;
  return null;
end $$;

create trigger org_units_provision_room
  after insert on org_units
  for each row execute function provision_unit_room();

create or replace function enrol_member_in_unit_room()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'active' then
    insert into chat_members (room_id, user_id)
    select r.id, new.user_id from chat_rooms r where r.org_unit_id = new.org_unit_id
    on conflict do nothing;
  end if;
  return null;
end $$;

create trigger memberships_enrol_chat
  after insert or update of status on memberships
  for each row execute function enrol_member_in_unit_room();

-- ============================================================================
--  SECTION 13 · SKILLS, PORTFOLIO & GAMIFICATION  (feature 4)
--
--  Three layers of personalisation, in increasing order of effort to build:
--    skills    — cheap, immediately useful ("who knows ROS2?")
--    projects  — the program's shared portfolio
--    badges    — engagement, awarded by rules, never by hand
-- ============================================================================

create table skills (
  id        uuid primary key default gen_random_uuid(),
  slug      text not null unique,
  name      text not null,
  -- 'embedded' | 'mechanical' | 'ai' | 'software' | 'electronics' | 'tooling'
  category  text not null,
  icon      text,
  color     text,
  -- Curated skills appear in the picker; user-suggested ones need approval,
  -- which keeps the tag list from degenerating into 200 spellings of "Arduino".
  is_curated boolean not null default true,
  created_at timestamptz not null default now()
);

create index skills_category_idx on skills (category);

create table user_skills (
  user_id    uuid not null references profiles(id) on delete cascade,
  skill_id   uuid not null references skills(id)   on delete cascade,
  -- Self-declared. 1 = belajar, 2 = bisa, 3 = mahir. Deliberately coarse:
  -- a finer scale invites inflation and means nothing.
  level      smallint not null default 2,
  is_pinned  boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, skill_id),
  constraint user_skills_level check (level between 1 and 3)
);

create index user_skills_skill_idx on user_skills (skill_id);

create table projects (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references profiles(id) on delete cascade,
  title        text not null,
  summary      text,
  description  text,
  cover_url    text,
  gallery      jsonb not null default '[]'::jsonb,
  repo_url     text,
  demo_url     text,
  video_url    text,
  -- Context: which course, lomba, or personal work it came from.
  context      text,
  subject_id   uuid references subjects(id) on delete set null,
  year         smallint,
  tags         text[] not null default '{}',

  is_public    boolean not null default true,
  is_pinned    boolean not null default false,
  sort_order   smallint not null default 0,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint projects_title_length check (length(btrim(title)) between 2 and 120),
  constraint projects_summary_length check (summary is null or length(summary) <= 280),
  constraint projects_gallery_array check (jsonb_typeof(gallery) = 'array'),
  constraint projects_repo_url check (repo_url is null or repo_url ~* '^https?://'),
  constraint projects_year_sane check (year is null or year between 2000 and 2100)
);

create index projects_owner_idx on projects (owner_id, sort_order);
create index projects_public_idx on projects (created_at desc) where is_public;
create index projects_tags_idx on projects using gin (tags);

create trigger projects_touch before update on projects
  for each row execute function touch_updated_at();

create table project_collaborators (
  project_id uuid not null references projects(id)  on delete cascade,
  user_id    uuid not null references profiles(id)  on delete cascade,
  role       text,                  -- 'Mekanik', 'Programmer', 'PCB'
  created_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table badges (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,
  name_id     text not null,
  name_en     text not null,
  description text not null,
  icon        text,
  -- 'bronze' | 'silver' | 'gold' | 'special'
  tier        text not null default 'bronze',
  -- Machine-readable award rule, evaluated by award_badges(). Keeping the rule
  -- as data means a new badge is an INSERT, not a deploy.
  rule        jsonb not null default '{}'::jsonb,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table user_badges (
  user_id    uuid not null references profiles(id) on delete cascade,
  badge_id   uuid not null references badges(id)   on delete cascade,
  awarded_at timestamptz not null default now(),
  context    jsonb not null default '{}'::jsonb,
  primary key (user_id, badge_id)
);

create index user_badges_recent_idx on user_badges (user_id, awarded_at desc);

create table user_stats (
  user_id            uuid primary key references profiles(id) on delete cascade,
  tasks_completed    int not null default 0,
  tasks_on_time      int not null default 0,
  tasks_late         int not null default 0,
  -- Consecutive days on which every due task was completed on time.
  streak_current     int not null default 0,
  streak_best        int not null default 0,
  streak_updated_on  date,
  messages_sent      int not null default 0,
  helpful_reactions  int not null default 0,
  updated_at         timestamptz not null default now()
);

create trigger user_stats_touch before update on user_stats
  for each row execute function touch_updated_at();

create or replace function ensure_user_stats()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into user_stats (user_id) values (new.id) on conflict do nothing;
  return null;
end $$;

create trigger profiles_create_stats
  after insert on profiles
  for each row execute function ensure_user_stats();

-- Recompute a student's counters and streak from their submissions. Called when
-- a submission changes; derived from source data so it is always reconcilable,
-- never drifting the way hand-incremented counters do.
create or replace function recompute_user_stats(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_on_time int; v_late int; v_done int;
  v_streak  int := 0; v_best int := 0; v_prev date; v_day date;
begin
  select count(*) filter (where state in ('submitted','done')),
         count(*) filter (where state in ('submitted','done') and not was_late),
         count(*) filter (where state in ('submitted','done') and was_late)
    into v_done, v_on_time, v_late
    from task_submissions where user_id = p_user;

  -- Streak = consecutive calendar days (WIB) with at least one on-time hand-in.
  for v_day in
    select distinct (submitted_at at time zone 'Asia/Jakarta')::date as d
      from task_submissions
     where user_id = p_user and not was_late and submitted_at is not null
     order by d desc
  loop
    if v_prev is null or v_prev - v_day = 1 then
      v_streak := v_streak + 1;
    else
      exit;
    end if;
    v_prev := v_day;
  end loop;

  select greatest(v_streak, coalesce(streak_best, 0)) into v_best
    from user_stats where user_id = p_user;

  insert into user_stats (user_id, tasks_completed, tasks_on_time, tasks_late,
                          streak_current, streak_best, streak_updated_on)
  values (p_user, v_done, v_on_time, v_late, v_streak,
          coalesce(v_best, v_streak), current_date)
  on conflict (user_id) do update
     set tasks_completed   = excluded.tasks_completed,
         tasks_on_time     = excluded.tasks_on_time,
         tasks_late        = excluded.tasks_late,
         streak_current    = excluded.streak_current,
         streak_best       = greatest(user_stats.streak_best, excluded.streak_current),
         streak_updated_on = current_date,
         updated_at        = now();
end $$;

create or replace function task_submissions_after_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform recompute_user_stats(new.user_id);
  return null;
end $$;

create trigger task_submissions_stats
  after insert or update of state on task_submissions
  for each row execute function task_submissions_after_write();

-- ============================================================================
--  SECTION 14 · AUDIT LOG
--
--  Structural changes only: roles, schedules, terms, org units, approvals.
--  Reads are deliberately NOT logged — recording who looked at whose profile
--  would be both useless for debugging and unpleasant for the students.
-- ============================================================================

create table audit_log (
  id          bigserial primary key,
  actor_id    uuid references profiles(id) on delete set null,
  action      text not null,          -- 'membership.approve', 'schedule.delete'
  entity_type text not null,
  entity_id   uuid,
  org_unit_id uuid references org_units(id) on delete set null,
  diff        jsonb not null default '{}'::jsonb,
  ip          inet,
  created_at  timestamptz not null default now()
);

create index audit_log_entity_idx on audit_log (entity_type, entity_id, created_at desc);
create index audit_log_actor_idx  on audit_log (actor_id, created_at desc);
create index audit_log_unit_idx   on audit_log (org_unit_id, created_at desc);

create or replace function write_audit(
  p_action text, p_entity_type text, p_entity_id uuid,
  p_org_unit uuid default null, p_diff jsonb default '{}'::jsonb
) returns void language sql security definer set search_path = public as $$
  insert into audit_log (actor_id, action, entity_type, entity_id, org_unit_id, diff)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_org_unit, p_diff);
$$;

-- Generic audit trigger for structural tables.
create or replace function audit_structural_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := case when tg_op = 'DELETE' then (old).id else (new).id end;
  insert into audit_log (actor_id, action, entity_type, entity_id, diff)
  values (
    auth.uid(),
    lower(tg_table_name) || '.' || lower(tg_op),
    tg_table_name,
    v_id,
    case tg_op
      when 'INSERT' then jsonb_build_object('new', to_jsonb(new))
      when 'DELETE' then jsonb_build_object('old', to_jsonb(old))
      else jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new))
    end
  );
  return null;
end $$;

create trigger memberships_audit
  after insert or update or delete on memberships
  for each row execute function audit_structural_change();

create trigger roles_audit
  after insert or update or delete on roles
  for each row execute function audit_structural_change();

create trigger org_units_audit
  after insert or update or delete on org_units
  for each row execute function audit_structural_change();

create trigger schedule_rules_audit
  after insert or update or delete on schedule_rules
  for each row execute function audit_structural_change();

create trigger academic_terms_audit
  after insert or update or delete on academic_terms
  for each row execute function audit_structural_change();

-- ============================================================================
--  SECTION 15 · DASHBOARD READ MODEL
--
--  One RPC returns everything the beranda needs, so a phone on campus WiFi
--  makes a single round trip instead of six. RLS still applies, because this is
--  SECURITY INVOKER (the default) — it runs as the calling student.
-- ============================================================================

create or replace function get_beranda(p_date date default null)
returns jsonb language sql stable as $$
  with me as (
    select p.id, p.primary_class_id, p.full_name, p.display_name
      from profiles p where p.id = auth.uid()
  ),
  d as (select coalesce(p_date, (now() at time zone 'Asia/Jakarta')::date) as day),
  today_sessions as (
    select jsonb_agg(jsonb_build_object(
             'id', ss.id,
             'subject', s.name,
             'subject_color', s.color,
             'lecturer', l.full_name,
             'room', ss.room,
             'kind', ss.kind,
             'starts_at', ss.starts_at,
             'ends_at', ss.ends_at,
             'status', ss.status,
             'note', ss.status_note
           ) order by ss.starts_at) as items
      from schedule_sessions ss
      join subjects s on s.id = ss.subject_id
      left join lecturers l on l.id = ss.lecturer_id
      cross join d
     where ss.class_id = (select primary_class_id from me)
       and ss.session_date = d.day
  ),
  upcoming_tasks as (
    select jsonb_agg(jsonb_build_object(
             'id', t.id,
             'title', t.title,
             'kind', t.kind,
             'priority', t.priority,
             'subject', s.name,
             'lecturer', l.full_name,
             'due_at', t.due_at,
             'state', coalesce(sub.state, 'todo'),
             'submit_channel', t.submit_channel
           ) order by t.due_at) as items
      from tasks t
      left join subjects s on s.id = t.subject_id
      left join lecturers l on l.id = t.lecturer_id
      left join task_submissions sub
             on sub.task_id = t.id and sub.user_id = auth.uid()
     where t.class_id = (select primary_class_id from me)
       and t.deleted_at is null
       and t.is_published
       and t.due_at between now() - interval '1 day' and now() + interval '14 days'
       and coalesce(sub.state, 'todo') not in ('done', 'skipped')
  )
  select jsonb_build_object(
    'date',           (select day from d),
    'class',          (select jsonb_build_object('id', o.id, 'code', o.code,
                                                 'name', o.name,
                                                 'semester', semester_of(o.entry_year))
                         from org_units o where o.id = (select primary_class_id from me)),
    'sessions',       coalesce((select items from today_sessions), '[]'::jsonb),
    'tasks',          coalesce((select items from upcoming_tasks), '[]'::jsonb),
    'unread_notifs',  (select count(*) from notifications
                        where user_id = auth.uid() and read_at is null),
    'unread_chats',   (select count(*) from chat_members cm
                        join chat_rooms r on r.id = cm.room_id
                       where cm.user_id = auth.uid()
                         and r.last_message_at is not null
                         and (cm.last_read_at is null or r.last_message_at > cm.last_read_at)),
    'stats',          (select to_jsonb(us) from user_stats us where us.user_id = auth.uid())
  );
$$;

comment on function get_beranda is
  'Single-round-trip dashboard payload. SECURITY INVOKER on purpose: RLS must '
  'still apply, so a student can never fetch another class''s data through it.';

-- ============================================================================
--  SECTION 16 · REALTIME PUBLICATION
-- ============================================================================

-- Only these tables stream to clients. RLS is enforced on the stream too, so a
-- student subscribed to chat_messages receives only rooms they belong to.
alter publication supabase_realtime add table chat_messages;
alter publication supabase_realtime add table chat_reactions;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table schedule_sessions;

-- ============================================================================
--  SECTION 17 · SCHEDULED JOBS (pg_cron)
--
--  Times are UTC; WIB = UTC+7. Register these once, after policies.sql.
-- ============================================================================

-- select cron.schedule('enqueue-class-reminders', '*/15 * * * *',
--   $$ select enqueue_upcoming_class_reminders(); $$);
--
-- select cron.schedule('generate-sessions-nightly', '0 18 * * *',   -- 01:00 WIB
--   $$ select generate_sessions_for_term(id) from academic_terms where is_current; $$);
--
-- select cron.schedule('mark-held-sessions', '*/30 * * * *',
--   $$ update schedule_sessions set status = 'held'
--       where status = 'scheduled' and ends_at < now(); $$);
--
-- select cron.schedule('prune-notification-jobs', '30 19 * * 0',    -- 02:30 WIB Sun
--   $$ delete from notification_jobs
--       where state in ('sent','cancelled','suppressed')
--         and created_at < now() - interval '60 days'; $$);
--
-- The actual delivery drain is an Edge Function invoked every minute by cron:
-- select cron.schedule('dispatch-notifications', '* * * * *',
--   $$ select net.http_post(
--        url := current_setting('app.edge_url') || '/dispatch-notifications',
--        headers := jsonb_build_object('Authorization',
--                   'Bearer ' || current_setting('app.service_key'))); $$);
