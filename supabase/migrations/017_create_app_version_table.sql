-- Migration 017: Create app_version table for In-App Auto Updates

CREATE TABLE IF NOT EXISTS public.app_version (
  id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  version_name TEXT NOT NULL,          -- e.g. "1.1.0"
  version_code INT NOT NULL,           -- e.g. 2 (buildNumber)
  min_version_name TEXT NOT NULL,      -- e.g. "1.0.0"
  min_version_code INT NOT NULL,       -- e.g. 1
  download_url TEXT NOT NULL,          -- Direct APK download link
  changelog TEXT NOT NULL,             -- Release notes / what's new
  force_update BOOLEAN DEFAULT false,  -- If true, user cannot dismiss dialog
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.app_version ENABLE ROW LEVEL SECURITY;

-- Allow public / authenticated read access
DROP POLICY IF EXISTS "Allow public read access to app_version" ON public.app_version;
CREATE POLICY "Allow public read access to app_version"
ON public.app_version
FOR SELECT
TO anon, authenticated
USING (is_active = true);

-- Insert initial version 1.1.0
INSERT INTO public.app_version (
  version_name,
  version_code,
  min_version_name,
  min_version_code,
  download_url,
  changelog,
  force_update,
  is_active
) VALUES (
  '1.1.0',
  2,
  '1.0.0',
  1,
  'https://pub-your-supabase-url.supabase.co/storage/v1/object/public/releases/app-release.apk',
  E'• Penambahan alur login 5 Operator Bidang (Komunikasi, Sandi Kami, Statistik, Aptika, Sekretariat)\n• Tampilan nama bidang lengkap di Menu Drawer & singkatan di Header\n• Kolom Pemohon surat otomatis mendukung format nama (Bidang)\n• Sistem In-App Auto Update otomatis',
  false,
  true
);
