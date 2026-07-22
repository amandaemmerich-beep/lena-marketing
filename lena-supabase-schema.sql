-- ============================================================
-- LENA · Banco de dados (Supabase / PostgreSQL)
-- Cole TODO este conteúdo no SQL Editor do Supabase e clique em "Run".
-- Cria: perfis de usuário, posts salvos, segurança (RLS) e o
-- comportamento de "1º usuário = administrador".
-- ============================================================

-- 1) PERFIS (1 por usuário, ligado ao login do Supabase)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text,
  role        text not null default 'user' check (role in ('user','admin')),
  state       jsonb not null default '{}'::jsonb,  -- estado do app (empresa, DNA, cores, etc.) — NÃO guarde chaves de API aqui
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- 2) POSTS SALVOS
create table if not exists public.posts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  tag         text,
  content     text,
  created_at  timestamptz default now()
);
create index if not exists posts_user_idx on public.posts(user_id);

-- 3) Ao criar um usuário, cria o perfil automaticamente.
--    O PRIMEIRO usuário do projeto vira 'admin'; os demais, 'user'.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    case when (select count(*) from public.profiles) = 0 then 'admin' else 'user' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4) Atualiza "updated_at" automaticamente
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- 5) Função auxiliar: "o usuário logado é admin?"
create or replace function public.is_admin()
returns boolean
language sql stable
security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 6) SEGURANÇA (Row Level Security)
alter table public.profiles enable row level security;
alter table public.posts    enable row level security;

-- PERFIS: cada um vê/edita o seu; o admin vê/edita todos
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (id = auth.uid() or public.is_admin());

-- POSTS: dono ou admin
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts
  for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts
  for insert with check (user_id = auth.uid());

drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts
  for delete using (user_id = auth.uid() or public.is_admin());

-- ============================================================
-- Pronto! Depois de rodar, o 1º cadastro no app será o ADMIN.
-- Para promover alguém a admin manualmente, rode:
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'email@da.pessoa');
-- ============================================================
