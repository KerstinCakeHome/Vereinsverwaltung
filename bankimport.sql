-- ============================================================
-- BANK-IMPORT (Kontoauszug als CAMT- oder CSV-Datei)  (Stand 05.10.2026)
--   * bank_konto:    Vereinskonto mit Startsaldo -> berechneter Kontostand
--   * bank_importe:  Protokoll jedes Imports (wer, wann, Zeitraum, Salden)
--   * zahlungen:     zusätzliche Felder für importierte Buchungen
-- Im Supabase SQL Editor ausführen. Ändert keine bestehenden Daten.
-- ============================================================

-- 1. Bankkonten des Vereins (in der Regel genau eins)
create table if not exists bank_konto (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references organizations(id) on delete cascade default current_user_org(),
    iban text not null,
    bezeichnung text,
    startsaldo numeric(12,2) not null default 0,     -- Kontostand vor der ersten importierten Buchung
    startdatum date not null,                         -- ab diesem Buchungstag zählt der Import
    bank_saldo numeric(12,2),                         -- letzter Kontostand laut Bank
    bank_saldo_datum date,
    erstellt_am timestamptz not null default now(),
    unique (organization_id, iban)
);

-- 2. Protokoll der Importe
create table if not exists bank_importe (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references organizations(id) on delete cascade default current_user_org(),
    bank_konto_id uuid references bank_konto(id) on delete set null,
    dateiname text,
    format text not null check (format in ('camt', 'csv', 'pdf')),
    zeitraum_von date,
    zeitraum_bis date,
    anfangssaldo numeric(12,2),
    endsaldo numeric(12,2),
    anzahl_neu integer not null default 0,
    anzahl_doppelt integer not null default 0,
    importiert_von uuid references profile(id) on delete set null default auth.uid(),
    importiert_am timestamptz not null default now()
);
create index if not exists idx_bank_importe_org on bank_importe(organization_id, importiert_am desc);

-- 3. Zusatzfelder an den Buchungen
alter table zahlungen add column if not exists gegenpartei text;
alter table zahlungen add column if not exists bank_konto_id uuid references bank_konto(id) on delete set null;
alter table zahlungen add column if not exists import_id uuid references bank_importe(id) on delete set null;
create index if not exists idx_zahlungen_bank_konto on zahlungen(bank_konto_id, datum);

-- 4. Zugriffsregeln: lesen Vorsitz/Kasse/Admin, schreiben Kasse/Admin
alter table bank_konto enable row level security;
alter table bank_importe enable row level security;
revoke all on bank_konto from anon;
revoke all on bank_importe from anon;

drop policy if exists "Bankkonto lesen" on bank_konto;
create policy "Bankkonto lesen" on bank_konto for select
    using (organization_id = current_user_org()
           and current_user_rolle() in ('admin', 'kassenwart', 'vorsitzender'));
drop policy if exists "Bankkonto anlegen" on bank_konto;
create policy "Bankkonto anlegen" on bank_konto for insert
    with check (organization_id = current_user_org()
                and current_user_rolle() in ('admin', 'kassenwart'));
drop policy if exists "Bankkonto aendern" on bank_konto;
create policy "Bankkonto aendern" on bank_konto for update
    using (organization_id = current_user_org()
           and current_user_rolle() in ('admin', 'kassenwart'));

drop policy if exists "Bankimporte lesen" on bank_importe;
create policy "Bankimporte lesen" on bank_importe for select
    using (organization_id = current_user_org()
           and current_user_rolle() in ('admin', 'kassenwart', 'vorsitzender'));
drop policy if exists "Bankimporte anlegen" on bank_importe;
create policy "Bankimporte anlegen" on bank_importe for insert
    with check (organization_id = current_user_org()
                and current_user_rolle() in ('admin', 'kassenwart'));
-- Import-Protokoll ist unveränderbar (keine Update-/Delete-Regel)
