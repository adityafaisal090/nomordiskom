-- ============================================================================
-- DATABASE WEBHOOK: Trigger send-push Edge Function on notifications INSERT
-- Jalankan ini di Supabase SQL Editor
-- ============================================================================

-- 1. Aktifkan extension pg_net (untuk HTTP request dari database)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Aktifkan Supabase Realtime untuk tabel notifications dan agenda_numbers
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.agenda_numbers;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 3. Buat trigger function yang memanggil Edge Function send-push
CREATE OR REPLACE FUNCTION public.notify_send_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net
AS $$
DECLARE
  v_url text;
  v_anon_key text;
BEGIN
  -- URL Edge Function send-push
  v_url := 'https://afqsalcedeloenwcngji.supabase.co/functions/v1/send-push';

  -- Anon key project Supabase Anda
  v_anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmcXNhbGNlZGVsb2Vud2NuZ2ppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU2ODIyOTAsImV4cCI6MjEwMTI1ODI5MH0.SV3gG1PwtWkWzGCIX-K6xWMxp9RiegJSqj5P49phwC4';

  -- Kirim HTTP POST ke Edge Function via net.http_post (body bertipe jsonb)
  PERFORM net.http_post(
    url := v_url,
    body := json_build_object('record', row_to_json(NEW))::jsonb,
    headers := json_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key,
      'apikey', v_anon_key
    )::jsonb
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Agar pembuatan nomor surat tetap sukses dan tidak terhalang
  RAISE WARNING 'Webhook send-push warning: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- 4. Hapus trigger lama jika ada
DROP TRIGGER IF EXISTS on_notification_insert_send_push ON public.notifications;

-- 5. Buat trigger pada tabel notifications
CREATE TRIGGER on_notification_insert_send_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_send_push();
