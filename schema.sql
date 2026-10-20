-- Tabla para guardar los clips generados con Clipper Studio
create table media_clips (
  id uuid default gen_random_uuid() primary key,
    user_id text default 'guest_user',
      title text not null,
        start_time int not null,
          end_time int not null,
            duration int generated always as (end_time - start_time) stored,
              aspect_ratio text default '9:16',
                clip_url text,
                  status text default 'processing', -- processing, ready, failed
                    created_at timestamp with time zone default timezone('utc'::text, now()) not null
                    );

                    -- Tabla para guardar las emisoras de Radio B2B
                    create table radio_stations (
                      id uuid default gen_random_uuid() primary key,
                        name text not null,
                          genre text,
                            stream_url text not null,
                              bitrate text default '320 kbps',
                                is_live boolean default true,
                                  created_at timestamp with time zone default timezone('utc'::text, now()) not null
                                  );

                                  -- Insertar emisora de prueba
                                  insert into radio_stations (name, genre, stream_url) 
                                  values ('Rock FM Digital 98.5', 'Rock/Classic', 'https://stream.example.com/rockfm');

-- Restrict saved clip metadata to its authenticated owner.
alter table public.media_clips enable row level security;

drop policy if exists "Users can read their own clips" on public.media_clips;
create policy "Users can read their own clips"
  on public.media_clips for select to authenticated
  using (user_id = (select auth.uid()::text));

drop policy if exists "Users can save their own clips" on public.media_clips;
create policy "Users can save their own clips"
  on public.media_clips for insert to authenticated
  with check (user_id = (select auth.uid()::text));

-- Keep uploaded originals and generated clips private in per-user folders.
insert into storage.buckets (id, name, public)
values ('user-media', 'user-media', false)
on conflict (id) do update set public = false;

drop policy if exists "Users can upload to their own media folder" on storage.objects;
create policy "Users can upload to their own media folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'user-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can read their own media" on storage.objects;
create policy "Users can read their own media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'user-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can delete their own media" on storage.objects;
create policy "Users can delete their own media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'user-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

-- Store uploaded video metadata separately from the media-clips table.
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  visibility text not null default 'public'
    check (visibility in ('public', 'private', 'link')),
  video_path text not null unique,
  created_at timestamptz not null default timezone('utc'::text, now())
);

alter table public.videos enable row level security;

drop policy if exists "Anyone can read public videos" on public.videos;
create policy "Anyone can read public videos"
  on public.videos for select to anon, authenticated
  using (visibility = 'public');

drop policy if exists "Users can read their own videos" on public.videos;
create policy "Users can read their own videos"
  on public.videos for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can upload their own videos" on public.videos;
create policy "Users can upload their own videos"
  on public.videos for insert to authenticated
  with check (user_id = (select auth.uid()));

create table if not exists public.subscripciones (
  id uuid primary key default gen_random_uuid(),
  suscriptor_id uuid not null references auth.users(id) on delete cascade,
  canal_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc'::text, now()),
  constraint subscripciones_unicas unique (suscriptor_id, canal_id),
  constraint subscripciones_no_propio_canal check (suscriptor_id <> canal_id)
);

alter table public.subscripciones enable row level security;

drop policy if exists "Users can read their own subscriptions" on public.subscripciones;
create policy "Users can read their own subscriptions"
  on public.subscripciones for select to authenticated
  using (suscriptor_id = (select auth.uid()));

drop policy if exists "Users can subscribe as themselves" on public.subscripciones;
create policy "Users can subscribe as themselves"
  on public.subscripciones for insert to authenticated
  with check (
    suscriptor_id = (select auth.uid())
    and suscriptor_id <> canal_id
  );

drop policy if exists "Users can unsubscribe themselves" on public.subscripciones;
create policy "Users can unsubscribe themselves"
  on public.subscripciones for delete to authenticated
  using (suscriptor_id = (select auth.uid()));

grant select, insert, delete on table public.subscripciones to authenticated;

create or replace function public.contar_suscriptores(p_canal_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)
  from public.subscripciones
  where canal_id = p_canal_id;
$$;

revoke all on function public.contar_suscriptores(uuid) from public;
grant execute on function public.contar_suscriptores(uuid) to anon, authenticated;

insert into storage.buckets (id, name, public)
values ('videos', 'videos', false)
on conflict (id) do update set public = false;

drop policy if exists "Users can upload to their own videos folder" on storage.objects;
create policy "Users can upload to their own videos folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'videos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can read their own videos and public videos" on storage.objects;
create policy "Users can read their own videos and public videos"
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'videos'
    and (
      (storage.foldername(name))[1] = (select auth.uid()::text)
      or exists (
        select 1
        from public.videos
        where video_path = storage.objects.name
          and visibility = 'public'
      )
    )
  );

drop policy if exists "Users can delete their own videos" on storage.objects;
create policy "Users can delete their own videos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'videos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
                                  