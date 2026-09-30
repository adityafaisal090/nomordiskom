-- ============================================================================
-- SIAGENDA Sprint 2 — Supabase PostgreSQL Migration
-- Tables: year_counters, daily_buffers, agenda_numbers, template_settings
-- RPC Functions: issue_today_number, generate_daily_buffer, issue_backdate_number
-- ============================================================================

-- ────────────────────────────────────────────
-- 1. TABLES
-- ────────────────────────────────────────────

-- 3.2 template_settings
CREATE TABLE IF NOT EXISTS public.template_settings (
    id SERIAL PRIMARY KEY,
    template_tetap VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.3 year_counters — counter global per tahun
CREATE TABLE IF NOT EXISTS public.year_counters (
    tahun INTEGER PRIMARY KEY,
    next_number INTEGER NOT NULL DEFAULT 1
);

-- 3.4 daily_buffers — stok nomor cadangan per tanggal
CREATE TABLE IF NOT EXISTS public.daily_buffers (
    id SERIAL PRIMARY KEY,
    tanggal DATE NOT NULL,
    tahun INTEGER NOT NULL,
    nomor INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'tersedia'
        CHECK (status IN ('tersedia', 'terpakai'))
);

-- 3.5 agenda_numbers — data utama nomor agenda
CREATE TABLE IF NOT EXISTS public.agenda_numbers (
    id SERIAL PRIMARY KEY,
    tahun INTEGER NOT NULL,
    nomor_agenda INTEGER NOT NULL,
    nomor_lengkap TEXT NOT NULL,
    kategori VARCHAR(30) NOT NULL
        CHECK (kategori IN ('surat_keputusan', 'nota_dinas', 'surat_keluar')),
    kode_klasifikasi VARCHAR(50) NOT NULL,
    kepada TEXT NOT NULL,
    perihal TEXT NOT NULL,
    pemohon VARCHAR(100) NOT NULL,
    tanggal_agenda DATE NOT NULL,
    is_backdate BOOLEAN NOT NULL DEFAULT false,
    dibuat_oleh UUID NOT NULL,  -- Supabase Auth user ID
    status_acc VARCHAR(20) NOT NULL DEFAULT 'menunggu'
        CHECK (status_acc IN ('menunggu', 'disetujui', 'ditolak')),
    catatan_admin TEXT,
    diacc_oleh UUID,            -- Supabase Auth user ID
    diacc_pada TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ────────────────────────────────────────────
-- 2. INDEXES
-- ────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_agenda_numbers_status ON public.agenda_numbers(status_acc);
CREATE INDEX IF NOT EXISTS idx_agenda_numbers_tanggal ON public.agenda_numbers(tanggal_agenda);
CREATE INDEX IF NOT EXISTS idx_agenda_numbers_tahun ON public.agenda_numbers(tahun);
CREATE INDEX IF NOT EXISTS idx_daily_buffers_tanggal ON public.daily_buffers(tanggal, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_buffers_unique ON public.daily_buffers(tanggal, nomor);

-- ────────────────────────────────────────────
-- 3. SEED DATA
-- ────────────────────────────────────────────

-- Default template (35.07.315) — insert if not exists
INSERT INTO public.template_settings (template_tetap, is_active)
SELECT '35.07.315', true
WHERE NOT EXISTS (SELECT 1 FROM public.template_settings WHERE is_active = true);

-- Year counter for current year — insert if not exists
INSERT INTO public.year_counters (tahun, next_number)
VALUES (EXTRACT(YEAR FROM now())::INTEGER, 1)
ON CONFLICT (tahun) DO NOTHING;

-- ────────────────────────────────────────────
-- 4. RPC FUNCTIONS
-- ────────────────────────────────────────────

-- ═══════════════════════════════════════════
-- 4.1 issue_today_number
-- Implements design.md §4.1 — EXACTLY
-- Transaction + SELECT ... FOR UPDATE on year_counters
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.issue_today_number(
    p_kategori VARCHAR,
    p_kode_klasifikasi VARCHAR,
    p_kepada TEXT,
    p_perihal TEXT,
    p_pemohon VARCHAR,
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tahun INTEGER;
    v_nomor INTEGER;
    v_template TEXT;
    v_nomor_lengkap TEXT;
    v_today DATE;
    v_record public.agenda_numbers%ROWTYPE;
BEGIN
    -- Current date in WIB (Asia/Jakarta)
    v_today := (now() AT TIME ZONE 'Asia/Jakarta')::DATE;
    v_tahun := EXTRACT(YEAR FROM v_today)::INTEGER;

    -- Ensure year_counter row exists (lazy-create for new year)
    INSERT INTO public.year_counters (tahun, next_number)
    VALUES (v_tahun, 1)
    ON CONFLICT (tahun) DO NOTHING;

    -- Lock the year_counter row — prevents concurrent duplicate numbers
    SELECT next_number INTO v_nomor
    FROM public.year_counters
    WHERE tahun = v_tahun
    FOR UPDATE;

    -- Advance the counter
    UPDATE public.year_counters
    SET next_number = next_number + 1
    WHERE tahun = v_tahun;

    -- Get active template
    SELECT template_tetap INTO v_template
    FROM public.template_settings
    WHERE is_active = true
    LIMIT 1;

    IF v_template IS NULL THEN
        RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
    END IF;

    -- Format: kode_klasifikasi / nomor_agenda / template_tetap/tahun
    v_nomor_lengkap := p_kode_klasifikasi || ' / ' || v_nomor::TEXT || ' / ' || v_template || '/' || v_tahun::TEXT;

    -- Insert the agenda number record
    INSERT INTO public.agenda_numbers (
        tahun, nomor_agenda, nomor_lengkap, kategori, kode_klasifikasi,
        kepada, perihal, pemohon, tanggal_agenda, is_backdate,
        dibuat_oleh, status_acc
    ) VALUES (
        v_tahun, v_nomor, v_nomor_lengkap, p_kategori, p_kode_klasifikasi,
        p_kepada, p_perihal, p_pemohon, v_today, false,
        p_user_id, 'menunggu'
    )
    RETURNING * INTO v_record;

    -- Return the full record as JSON
    RETURN jsonb_build_object(
        'id', v_record.id,
        'tahun', v_record.tahun,
        'nomor_agenda', v_record.nomor_agenda,
        'nomor_lengkap', v_record.nomor_lengkap,
        'kategori', v_record.kategori,
        'kode_klasifikasi', v_record.kode_klasifikasi,
        'kepada', v_record.kepada,
        'perihal', v_record.perihal,
        'pemohon', v_record.pemohon,
        'tanggal_agenda', v_record.tanggal_agenda,
        'is_backdate', v_record.is_backdate,
        'dibuat_oleh', v_record.dibuat_oleh,
        'status_acc', v_record.status_acc,
        'created_at', v_record.created_at
    );
END;
$$;


-- ═══════════════════════════════════════════
-- 4.2 generate_daily_buffer
-- Implements design.md §4.2
-- Generates 10 buffer numbers for a given date
-- Idempotent: skips if buffers already exist for that date
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.generate_daily_buffer(
    p_tanggal DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tahun INTEGER;
    v_next INTEGER;
    v_existing INTEGER;
    i INTEGER;
BEGIN
    v_tahun := EXTRACT(YEAR FROM p_tanggal)::INTEGER;

    -- Check if buffers already exist for this date (idempotent)
    SELECT COUNT(*) INTO v_existing
    FROM public.daily_buffers
    WHERE tanggal = p_tanggal;

    IF v_existing > 0 THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Buffer sudah ada untuk tanggal ' || p_tanggal::TEXT,
            'count', v_existing,
            'skipped', true
        );
    END IF;

    -- Ensure year_counter row exists
    INSERT INTO public.year_counters (tahun, next_number)
    VALUES (v_tahun, 1)
    ON CONFLICT (tahun) DO NOTHING;

    -- Lock the year_counter row
    SELECT next_number INTO v_next
    FROM public.year_counters
    WHERE tahun = v_tahun
    FOR UPDATE;

    -- Generate 10 buffer numbers
    FOR i IN 0..9 LOOP
        INSERT INTO public.daily_buffers (tanggal, tahun, nomor, status)
        VALUES (p_tanggal, v_tahun, v_next + i, 'tersedia');
    END LOOP;

    -- Advance counter by 10
    UPDATE public.year_counters
    SET next_number = next_number + 10
    WHERE tahun = v_tahun;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Buffer berhasil digenerate untuk tanggal ' || p_tanggal::TEXT,
        'count', 10,
        'first_number', v_next,
        'last_number', v_next + 9,
        'skipped', false
    );
END;
$$;


-- ═══════════════════════════════════════════
-- 4.3 issue_backdate_number
-- Implements design.md §4.3
-- Takes 1 available buffer for the given date
-- FOR UPDATE SKIP LOCKED for concurrency safety
-- ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.issue_backdate_number(
    p_tanggal DATE,
    p_kategori VARCHAR,
    p_kode_klasifikasi VARCHAR,
    p_kepada TEXT,
    p_perihal TEXT,
    p_pemohon VARCHAR,
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_buffer_id INTEGER;
    v_nomor INTEGER;
    v_tahun INTEGER;
    v_template TEXT;
    v_nomor_lengkap TEXT;
    v_record public.agenda_numbers%ROWTYPE;
BEGIN
    v_tahun := EXTRACT(YEAR FROM p_tanggal)::INTEGER;

    -- Try to grab one available buffer for this date
    SELECT id, nomor INTO v_buffer_id, v_nomor
    FROM public.daily_buffers
    WHERE tanggal = p_tanggal AND status = 'tersedia'
    ORDER BY nomor ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    -- No buffer available
    IF v_buffer_id IS NULL THEN
        RAISE EXCEPTION 'Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
    END IF;

    -- Mark buffer as used
    UPDATE public.daily_buffers
    SET status = 'terpakai'
    WHERE id = v_buffer_id;

    -- Get active template
    SELECT template_tetap INTO v_template
    FROM public.template_settings
    WHERE is_active = true
    LIMIT 1;

    IF v_template IS NULL THEN
        RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
    END IF;

    -- Format nomor lengkap
    v_nomor_lengkap := p_kode_klasifikasi || ' / ' || v_nomor::TEXT || ' / ' || v_template || '/' || v_tahun::TEXT;

    -- Insert the agenda number record
    INSERT INTO public.agenda_numbers (
        tahun, nomor_agenda, nomor_lengkap, kategori, kode_klasifikasi,
        kepada, perihal, pemohon, tanggal_agenda, is_backdate,
        dibuat_oleh, status_acc
    ) VALUES (
        v_tahun, v_nomor, v_nomor_lengkap, p_kategori, p_kode_klasifikasi,
        p_kepada, p_perihal, p_pemohon, p_tanggal, true,
        p_user_id, 'menunggu'
    )
    RETURNING * INTO v_record;

    RETURN jsonb_build_object(
        'id', v_record.id,
        'tahun', v_record.tahun,
        'nomor_agenda', v_record.nomor_agenda,
        'nomor_lengkap', v_record.nomor_lengkap,
        'kategori', v_record.kategori,
        'kode_klasifikasi', v_record.kode_klasifikasi,
        'kepada', v_record.kepada,
        'perihal', v_record.perihal,
        'pemohon', v_record.pemohon,
        'tanggal_agenda', v_record.tanggal_agenda,
        'is_backdate', v_record.is_backdate,
        'dibuat_oleh', v_record.dibuat_oleh,
        'status_acc', v_record.status_acc,
        'created_at', v_record.created_at
    );
END;
$$;


-- ────────────────────────────────────────────
-- 5. ROW LEVEL SECURITY (RLS)
-- ────────────────────────────────────────────

-- Enable RLS on all tables
ALTER TABLE public.template_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.year_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_buffers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agenda_numbers ENABLE ROW LEVEL SECURITY;

-- template_settings: any authenticated user can read
CREATE POLICY "Authenticated users can read template_settings"
    ON public.template_settings FOR SELECT
    TO authenticated
    USING (true);

-- year_counters: no direct access (only via SECURITY DEFINER RPC)
-- No policy = no direct access from client

-- daily_buffers: no direct access (only via SECURITY DEFINER RPC)
-- No policy = no direct access from client

-- agenda_numbers: authenticated users can read all records
CREATE POLICY "Authenticated users can read agenda_numbers"
    ON public.agenda_numbers FOR SELECT
    TO authenticated
    USING (true);

-- agenda_numbers: operators can insert (but we mostly use RPC, this is a fallback)
CREATE POLICY "Authenticated users can insert agenda_numbers"
    ON public.agenda_numbers FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- agenda_numbers: operators can update their own records (for edit before ACC, Sprint 3)
CREATE POLICY "Authenticated users can update agenda_numbers"
    ON public.agenda_numbers FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);


-- ────────────────────────────────────────────
-- 6. GRANT EXECUTE on RPC functions to authenticated users
-- ────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.issue_today_number TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_daily_buffer TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_backdate_number TO authenticated;
