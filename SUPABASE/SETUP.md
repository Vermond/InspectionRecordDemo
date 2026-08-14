# Supabase 설정

이 문서는 데모 실행을 위한 Supabase 초기 설정을 정리한 문서입니다.
현재 RLS 정책은 인증이 없는 데모 환경을 기준으로 하며, 실제 서비스용 보안 설정이 아닙니다.

## 테이블 

```sql
create table public.inspection_targets (
    id uuid primary key,
    name text not null,
    equipment_number text not null,
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create table public.inspection_records (
    id uuid primary key,
    target_id uuid not null
        references public.inspection_targets(id)
        on delete restrict,
    target_name_snapshot text not null,
    equipment_number_snapshot text not null,
    status text,
    memo text not null default '',
    latitude double precision,
    longitude double precision,
    photo_path text,
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create index inspection_records_target_id_idx
    on public.inspection_records(target_id);

create index inspection_records_updated_at_idx
    on public.inspection_records(updated_at);
```

## RLS + 권한

```sql
alter table public.inspection_targets enable row level security;
alter table public.inspection_records enable row level security;

grant select, insert, update
on table public.inspection_targets
to anon;

grant select, insert, update
on table public.inspection_records
to anon;

create policy "anon can read inspection targets"
on public.inspection_targets
for select
to anon
using (true);

create policy "anon can insert inspection targets"
on public.inspection_targets
for insert
to anon
with check (true);

create policy "anon can update inspection targets"
on public.inspection_targets
for update
to anon
using (true)
with check (true);

create policy "anon can read inspection records"
on public.inspection_records
for select
to anon
using (true);

create policy "anon can insert inspection records"
on public.inspection_records
for insert
to anon
with check (true);

create policy "anon can update inspection records"
on public.inspection_records
for update
to anon
using (true)
with check (true);
```

## Storage

### Bucket 생성

```sql
insert into storage.buckets (id, name, public)
values (
    'inspection-photos',
    'inspection-photos',
    false
);
```

### Storage RLS 정책
```sql
create policy "anon can read inspection photos"
on storage.objects
for select
to anon
using (bucket_id = 'inspection-photos');

create policy "anon can upload inspection photos"
on storage.objects
for insert
to anon
with check (bucket_id = 'inspection-photos');

create policy "anon can update inspection photos"
on storage.objects
for update
to anon
using (bucket_id = 'inspection-photos')
with check (bucket_id = 'inspection-photos');

create policy "anon can delete inspection photos"
on storage.objects
for delete
to anon
using (bucket_id = 'inspection-photos');
```

## Edge Function

점검 기록과 사진 동기화에는 `sync-inspection` Edge Function을 사용합니다.

소스:
`supabase/functions/sync-inspection.ts`

## 클라이언트 설정

Supabase 프로젝트 생성 후 Project URL과 Publishable Key를 로컬 설정 파일에 지정합니다.

```xcconfig
SUPABASE_URL = ...
SUPABASE_PUBLISHABLE_KEY = ...
```

실제 설정값이 포함된 파일은 Git에 포함하지 않습니다.
