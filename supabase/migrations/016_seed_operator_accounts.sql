-- Migration 016: Seed / Update 5 Operator Accounts in Supabase Auth
-- Bidang Operator MONA:
-- 1. Komunikasi dan Informasi (Username: komunikasi, Pass: komunikasi123)
-- 2. Persandian dan Keamanan Informasi (Username: sandikami, Pass: sandikami123)
-- 3. Data dan Statistik (Username: statistik, Pass: statistik123)
-- 4. Aplikasi Informatika (Username: aptika, Pass: aptika123)
-- 5. Sekretariat (Username: sekretariat, Pass: sekretariat123)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_users JSONB := '[
    {
      "username": "komunikasi",
      "nama": "Komunikasi dan Informasi",
      "singkatan": "Komunikasi",
      "pass": "komunikasi123"
    },
    {
      "username": "sandikami",
      "nama": "Persandian dan Keamanan Informasi",
      "singkatan": "Sandi Kami",
      "pass": "sandikami123"
    },
    {
      "username": "statistik",
      "nama": "Data dan Statistik",
      "singkatan": "Statistik",
      "pass": "statistik123"
    },
    {
      "username": "aptika",
      "nama": "Aplikasi Informatika",
      "singkatan": "Aptika",
      "pass": "aptika123"
    },
    {
      "username": "sekretariat",
      "nama": "Sekretariat",
      "singkatan": "Sekretariat",
      "pass": "sekretariat123"
    }
  ]'::jsonb;
  v_u JSONB;
  v_email TEXT;
  v_user_id UUID;
BEGIN
  FOR v_u IN SELECT * FROM jsonb_array_elements(v_users)
  LOOP
    v_email := (v_u->>'username') || '@siagenda.local';
    
    SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
    
    IF v_user_id IS NULL THEN
      -- Insert user baru
      INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
      ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        v_email,
        crypt(v_u->>'pass', gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}',
        jsonb_build_object(
          'username', v_u->>'username',
          'nama', v_u->>'nama',
          'singkatan', v_u->>'singkatan',
          'role', 'operator'
        ),
        now(),
        now()
      );
    ELSE
      -- Update user yang sudah ada
      UPDATE auth.users
      SET 
        encrypted_password = crypt(v_u->>'pass', gen_salt('bf')),
        raw_user_meta_data = jsonb_build_object(
          'username', v_u->>'username',
          'nama', v_u->>'nama',
          'singkatan', v_u->>'singkatan',
          'role', 'operator'
        ),
        updated_at = now()
      WHERE id = v_user_id;
    END IF;
  END LOOP;
END $$;
