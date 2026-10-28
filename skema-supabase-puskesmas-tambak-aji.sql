-- =====================================================================
-- Skema Supabase: Website Puskesmas Tambak Aji
-- Jalankan di Supabase > SQL Editor. Tidak berisi data resmi (tidak ada
-- alamat, jadwal, visi misi, dsb.): semua diisi petugas lewat dashboard.
-- Kata sandi dikelola Supabase Auth (hash), tidak disimpan di tabel ini.
-- =====================================================================

-- 1. Peran dan akun admin ---------------------------------------------
create type peran_admin as enum ('super_admin', 'editor', 'petugas_posyandu');

create table admin_profil (
  id uuid primary key references auth.users(id) on delete cascade,
  nama text not null check (char_length(nama) between 2 and 100),
  peran peran_admin not null default 'editor',
  aktif boolean not null default true,
  dibuat_pada timestamptz not null default now()
);

-- Fungsi bantu: peran admin aktif milik pengguna yang sedang login
create or replace function peran_saya() returns peran_admin
language sql stable security definer set search_path = public as $$
  select peran from admin_profil where id = auth.uid() and aktif
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select peran_saya() is not null
$$;

-- Trigger pembaruan tanggal otomatis
create or replace function set_diperbarui() returns trigger language plpgsql as $$
begin new.diperbarui_pada = now(); return new; end $$;

-- 2. Profil puskesmas (satu baris) -------------------------------------
create table profil_puskesmas (
  id smallint primary key default 1 check (id = 1),
  nama text not null default 'Puskesmas Tambak Aji',
  tentang text,
  visi text,
  misi text,
  wilayah_kerja text,
  fasilitas text,
  alamat text,
  telepon text,
  whatsapp text,
  email text,
  jam_pelayanan text,
  media_sosial jsonb not null default '{}',
  latitude numeric(9,6),
  longitude numeric(9,6),
  diperbarui_pada timestamptz not null default now()
);
insert into profil_puskesmas (id) values (1);

-- 3. Informasi layanan (ILP dan lainnya) -------------------------------
create table layanan (
  id uuid primary key default gen_random_uuid(),
  klaster text not null check (klaster in
    ('ibu_anak_remaja','dewasa_lansia','penyakit_menular','lintas_klaster','umum')),
  nama text not null check (char_length(nama) between 3 and 150),
  deskripsi text,
  persyaratan text,
  prosedur text,
  biaya text,
  urutan int not null default 0,
  terbit boolean not null default false,
  diperbarui_pada timestamptz not null default now()
);

-- 4. Data posyandu dan jadwalnya ---------------------------------------
create table posyandu (
  id uuid primary key default gen_random_uuid(),
  nama text not null check (char_length(nama) between 3 and 120),
  kelurahan text not null,
  alamat text,
  aktif boolean not null default true,
  diperbarui_pada timestamptz not null default now()
);

create table jadwal_posyandu (
  id uuid primary key default gen_random_uuid(),
  posyandu_id uuid not null references posyandu(id) on delete cascade,
  tanggal date not null,
  jam_mulai time,
  jam_selesai time,
  jenis_kegiatan text not null,
  sasaran text,
  keterangan text,
  status text not null default 'terjadwal'
    check (status in ('terjadwal','diubah','dibatalkan')),
  catatan_perubahan text,
  terbit boolean not null default false,
  diperbarui_pada timestamptz not null default now(),
  check (jam_selesai is null or jam_mulai is null or jam_selesai > jam_mulai)
);
create index on jadwal_posyandu (tanggal);
create index on jadwal_posyandu (posyandu_id);

-- 5. Pengumuman -----------------------------------------------------------
create table pengumuman (
  id uuid primary key default gen_random_uuid(),
  judul text not null check (char_length(judul) between 5 and 200),
  isi text not null,
  kategori text not null default 'umum' check (kategori in
    ('jadwal_pelayanan','hari_libur','kegiatan','layanan_kesehatan','umum')),
  tanggal_terbit date not null default current_date,
  terbit boolean not null default false,
  dibuat_oleh uuid references admin_profil(id),
  diperbarui_pada timestamptz not null default now()
);

-- 6. Berita dan artikel kesehatan -----------------------------------------
create table berita_artikel (
  id uuid primary key default gen_random_uuid(),
  jenis text not null check (jenis in ('berita','artikel')),
  judul text not null check (char_length(judul) between 5 and 200),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  kategori text not null,
  ringkasan text,
  isi text not null,
  gambar_url text,
  sumber_referensi text,
  tanggal_terbit date not null default current_date,
  terbit boolean not null default false,
  dibuat_oleh uuid references admin_profil(id),
  diperbarui_pada timestamptz not null default now()
);
create index on berita_artikel (jenis, tanggal_terbit desc);

-- 7. Dokumen publik ----------------------------------------------------------
create table dokumen_publik (
  id uuid primary key default gen_random_uuid(),
  judul text not null check (char_length(judul) between 3 and 200),
  kategori text not null check (kategori in
    ('profil','standar_pelayanan','brosur','leaflet','laporan','lainnya')),
  file_path text not null,   -- path di Supabase Storage bucket "dokumen-publik"
  ukuran_byte bigint,
  tanggal_terbit date not null default current_date,
  terbit boolean not null default false,
  diperbarui_pada timestamptz not null default now()
);

-- 8. Galeri kegiatan -----------------------------------------------------------
create table galeri (
  id uuid primary key default gen_random_uuid(),
  judul text not null,
  kategori text not null,
  file_path text not null,   -- bucket "galeri-kegiatan"
  teks_alternatif text not null,  -- untuk aksesibilitas
  tanggal_kegiatan date,
  terbit boolean not null default false,
  diperbarui_pada timestamptz not null default now()
);

-- 9. Pesan formulir kontak -------------------------------------------------------
create table pesan_kontak (
  id uuid primary key default gen_random_uuid(),
  nama text not null check (char_length(nama) between 2 and 100),
  kontak text check (char_length(kontak) <= 120),
  kategori text not null,
  subjek text not null check (char_length(subjek) between 3 and 150),
  isi text not null check (char_length(isi) between 10 and 2000),
  status text not null default 'baru' check (status in ('baru','dibaca','ditindaklanjuti')),
  dibuat_pada timestamptz not null default now()
);

-- Trigger tanggal pembaruan untuk semua tabel yang punya kolomnya
do $$
declare t text;
begin
  foreach t in array array['profil_puskesmas','layanan','posyandu','jadwal_posyandu',
    'pengumuman','berita_artikel','dokumen_publik','galeri'] loop
    execute format('create trigger trg_%1$s_upd before update on %1$I
      for each row execute function set_diperbarui()', t);
  end loop;
end $$;

-- 10. Row Level Security -----------------------------------------------------------
alter table admin_profil     enable row level security;
alter table profil_puskesmas enable row level security;
alter table layanan          enable row level security;
alter table posyandu         enable row level security;
alter table jadwal_posyandu  enable row level security;
alter table pengumuman       enable row level security;
alter table berita_artikel   enable row level security;
alter table dokumen_publik   enable row level security;
alter table galeri           enable row level security;
alter table pesan_kontak     enable row level security;

-- Admin: hanya super_admin yang mengelola akun; admin lain bisa melihat profil sendiri
create policy admin_lihat_sendiri on admin_profil for select
  using (id = auth.uid() or peran_saya() = 'super_admin');
create policy admin_kelola on admin_profil for all
  using (peran_saya() = 'super_admin') with check (peran_saya() = 'super_admin');

-- Publik boleh membaca profil dan data posyandu
create policy publik_baca on profil_puskesmas for select using (true);
create policy publik_baca on posyandu for select using (aktif);
-- Konten publik: hanya yang sudah terbit
create policy publik_baca on layanan         for select using (terbit);
create policy publik_baca on jadwal_posyandu for select using (terbit);
create policy publik_baca on pengumuman      for select using (terbit);
create policy publik_baca on berita_artikel  for select using (terbit);
create policy publik_baca on dokumen_publik  for select using (terbit);
create policy publik_baca on galeri          for select using (terbit);

-- Admin membaca semua (termasuk draf)
create policy admin_baca on layanan         for select using (is_admin());
create policy admin_baca on jadwal_posyandu for select using (is_admin());
create policy admin_baca on pengumuman      for select using (is_admin());
create policy admin_baca on berita_artikel  for select using (is_admin());
create policy admin_baca on dokumen_publik  for select using (is_admin());
create policy admin_baca on galeri          for select using (is_admin());

-- Penulisan berdasarkan peran
create policy tulis_super on profil_puskesmas for update
  using (peran_saya() = 'super_admin') with check (peran_saya() = 'super_admin');

create policy tulis_editor on layanan for all
  using (peran_saya() in ('super_admin','editor'))
  with check (peran_saya() in ('super_admin','editor'));
create policy tulis_editor on pengumuman for all
  using (peran_saya() in ('super_admin','editor'))
  with check (peran_saya() in ('super_admin','editor'));
create policy tulis_editor on berita_artikel for all
  using (peran_saya() in ('super_admin','editor'))
  with check (peran_saya() in ('super_admin','editor'));
create policy tulis_editor on dokumen_publik for all
  using (peran_saya() in ('super_admin','editor'))
  with check (peran_saya() in ('super_admin','editor'));
create policy tulis_editor on galeri for all
  using (peran_saya() in ('super_admin','editor'))
  with check (peran_saya() in ('super_admin','editor'));

create policy tulis_posyandu on posyandu for all
  using (peran_saya() in ('super_admin','petugas_posyandu'))
  with check (peran_saya() in ('super_admin','petugas_posyandu'));
create policy tulis_posyandu on jadwal_posyandu for all
  using (peran_saya() in ('super_admin','petugas_posyandu'))
  with check (peran_saya() in ('super_admin','petugas_posyandu'));

-- Formulir kontak: publik hanya boleh MENGIRIM (status wajib 'baru'), tidak boleh membaca
create policy kirim_pesan on pesan_kontak for insert
  to anon, authenticated with check (status = 'baru');
create policy admin_kelola_pesan on pesan_kontak for select
  using (peran_saya() in ('super_admin','editor'));
create policy admin_ubah_pesan on pesan_kontak for update
  using (peran_saya() in ('super_admin','editor'))
  with check (peran_saya() in ('super_admin','editor'));
create policy admin_hapus_pesan on pesan_kontak for delete
  using (peran_saya() = 'super_admin');

-- 11. Storage ----------------------------------------------------------------------
-- Buat bucket "dokumen-publik" dan "galeri-kegiatan" (public read) lewat
-- Dashboard > Storage. Batasi unggah (hanya admin, tipe PDF/JPG/PNG/WEBP,
-- ukuran maksimum, mis. 5 MB) dengan policy pada storage.objects, misalnya:
--   create policy unggah_admin on storage.objects for insert to authenticated
--   with check (bucket_id in ('dokumen-publik','galeri-kegiatan') and is_admin());

-- 12. Catatan keamanan dan operasional -----------------------------------------------
-- * Frontend hanya memakai anon key. service_role key JANGAN ditaruh di frontend.
-- * Aktifkan konfirmasi email, kebijakan kata sandi kuat, dan MFA untuk admin.
-- * Tambahkan CAPTCHA/rate limit pada formulir kontak untuk mencegah spam.
-- * Jangan menulis data pasien atau rekam medis di tabel mana pun.
-- * Aktifkan backup harian (Supabase Pro: PITR) dan uji pemulihan berkala.
