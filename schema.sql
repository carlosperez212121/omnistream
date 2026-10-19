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
                                  