# backend/test_scripts/seed_data.py
from sqlalchemy import text
from backend.utils.database_utils import SessionLocal


def seed():
    db = SessionLocal()
    try:

        # ── 1. PROJECT ──────────────────────────────────────────────────────────
        db.execute(text("""
            INSERT INTO dim_project
                (project_code, project_name, client_name, project_country,
                 project_city, receiving_port, start_date, end_date, status)
            VALUES
                ('PRJ-001', 'Offshore Wind Farm Alpha', 'North Sea Energy GmbH',
                 'Singapore', 'Singapore', 'Port of Singapore',
                 '2024-01-01', '2025-12-31', 'active'),
                ('PRJ-002', 'Solar Grid Expansion Beta', 'SolarCorp Asia',
                 'Malaysia', 'Kuala Lumpur', 'Port Klang',
                 '2024-03-01', '2025-06-30', 'active')
            ON CONFLICT (project_code) DO NOTHING;
        """))
        print("✅ dim_project seeded")

        # ── 2. SUPPLIERS ────────────────────────────────────────────────────────
        # FIX: supplier_code → supplier_number  (matches your create_table.sql)
        db.execute(text("""
            INSERT INTO dim_supplier
                (supplier_number, supplier_name, country, region, city,
                 shipping_port, risk_tier)
            VALUES
                ('SUP-001', 'Siemens Energy AG',          'Germany',     'Europe',        'Hamburg',   'Port of Hamburg',    1),
                ('SUP-002', 'CSSC Shipping Co.',           'China',       'Asia Pacific',  'Shanghai',  'Port of Shanghai',   3),
                ('SUP-003', 'ABB Ltd',                     'Netherlands', 'Europe',        'Rotterdam', 'Port of Rotterdam',  1),
                ('SUP-004', 'Hitachi Energy Ltd',          'Japan',       'Asia Pacific',  'Yokohama',  'Port of Yokohama',   2),
                ('SUP-005', 'Schneider Electric SE',       'France',      'Europe',        'Paris',     'Port of Le Havre',   1),
                ('SUP-006', 'Bharat Heavy Electricals',    'India',       'South Asia',    'Mumbai',    'Nhava Sheva Port',   2)
            ON CONFLICT (supplier_number) DO NOTHING;
        """))
        print("✅ dim_supplier seeded")

        # ── 3. EQUIPMENT ────────────────────────────────────────────────────────
        db.execute(text("""
            INSERT INTO dim_equipment
                (equipment_code, equipment_name, equipment_type, specifications,
                 criticality, lead_time_days, hs_code)
            VALUES
                ('EQ-001', 'Main Transformer 400kV',  'transformer',  '400kV, 250MVA, ONAN/ONAF cooling',    'critical', 180, '8504.21'),
                ('EQ-002', 'GIS Switchgear 132kV',    'switchgear',   '132kV, SF6 insulated, 12-panel bay',  'critical', 150, '8537.10'),
                ('EQ-003', 'Diesel Generator 2MW',    'generator',    '2MW, 11kV, Cummins engine, IP54',     'high',     120, '8502.11'),
                ('EQ-004', 'MV Switchboard',          'switchgear',   '33kV, 8-feeder, draw-out type',       'high',     90,  '8537.20'),
                ('EQ-005', 'Protection Panel',        'panel',        'Numerical protection, IEC 61850',     'medium',   60,  '8537.10'),
                ('EQ-006', 'Offshore Crane 50T',      'crane',        '50T SWL, pedestal-mounted, offshore', 'critical', 210, '8426.20'),
                ('EQ-007', 'HV Cable System',         'cable',        '132kV XLPE submarine cable, 15km',   'critical', 240, '8544.60'),
                ('EQ-008', 'Battery Storage BESS',    'storage',      '10MWh Li-ion BESS, 11kV grid-tie',   'high',     150, '8507.60')
            ON CONFLICT (equipment_code) DO NOTHING;
        """))
        print("✅ dim_equipment seeded")

        # ── 4. MILESTONES ───────────────────────────────────────────────────────
        db.execute(text("""
            INSERT INTO dim_milestone
                (milestone_code, milestone_activity, milestone_description,
                 milestone_type, sequence_order)
            VALUES
                ('MS-01', 'Purchase Order Issued',      'PO issued to supplier',                     'procurement',    1),
                ('MS-02', 'Engineering Design Complete','Approved for manufacture drawings issued',   'design',         2),
                ('MS-03', 'Material Procurement',       'Raw materials procured by supplier',        'manufacturing',  3),
                ('MS-04', 'Manufacturing Start',        'Production commenced at factory',           'manufacturing',  4),
                ('MS-05', 'Factory Acceptance Test',    'FAT completed and witnessed',               'inspection',     5),
                ('MS-06', 'Ready for Shipment',         'Equipment packed and ready at factory',     'shipping',       6),
                ('MS-07', 'Shipment Departed',          'Vessel departed origin port',               'shipping',       7),
                ('MS-08', 'Shipment Arrived',           'Vessel arrived at destination port',        'shipping',       8),
                ('MS-09', 'Customs Cleared',            'Import customs clearance completed',        'shipping',       9),
                ('MS-10', 'Site Delivery',              'Equipment delivered to project site',       'delivery',      10)
            ON CONFLICT (milestone_activity, milestone_description) DO NOTHING;
        """))
        print("✅ dim_milestone seeded")

        # ── 5. WORK PACKAGE ─────────────────────────────────────────────────────
        db.execute(text("""
            INSERT INTO dim_work_package
                (project_id, work_package_code, work_package_name, wbs,
                 responsible_party, start_date, end_date, status)
            VALUES
                (
                    (SELECT project_id FROM dim_project WHERE project_code = 'PRJ-001'),
                    'WP-001', 'Electrical Equipment Procurement',
                    '1.2.1', 'Procurement Team',
                    '2024-01-01', '2025-06-30', 'active'
                ),
                (
                    (SELECT project_id FROM dim_project WHERE project_code = 'PRJ-001'),
                    'WP-002', 'Marine & Lifting Equipment',
                    '1.2.2', 'Marine Team',
                    '2024-03-01', '2025-09-30', 'active'
                )
            ON CONFLICT (work_package_code) DO NOTHING;
        """))
        print("✅ dim_work_package seeded")

        # ── 6. EQUIPMENT ↔ SUPPLIER BRIDGE ─────────────────────────────────────
        db.execute(text("""
            INSERT INTO dim_equipment_supplier
                (equipment_id, supplier_id, is_primary)
            VALUES
                (
                    (SELECT equipment_id FROM dim_equipment WHERE equipment_code = 'EQ-001'),
                    (SELECT supplier_id  FROM dim_supplier  WHERE supplier_number = 'SUP-001'),
                    TRUE
                ),
                (
                    (SELECT equipment_id FROM dim_equipment WHERE equipment_code = 'EQ-002'),
                    (SELECT supplier_id  FROM dim_supplier  WHERE supplier_number = 'SUP-003'),
                    TRUE
                ),
                (
                    (SELECT equipment_id FROM dim_equipment WHERE equipment_code = 'EQ-003'),
                    (SELECT supplier_id  FROM dim_supplier  WHERE supplier_number = 'SUP-004'),
                    TRUE
                ),
                (
                    (SELECT equipment_id FROM dim_equipment WHERE equipment_code = 'EQ-004'),
                    (SELECT supplier_id  FROM dim_supplier  WHERE supplier_number = 'SUP-005'),
                    TRUE
                ),
                (
                    (SELECT equipment_id FROM dim_equipment WHERE equipment_code = 'EQ-006'),
                    (SELECT supplier_id  FROM dim_supplier  WHERE supplier_number = 'SUP-002'),
                    TRUE
                )
            ON CONFLICT (equipment_id, supplier_id) DO NOTHING;
        """))
        print("✅ dim_equipment_supplier seeded")

        # ── 7. MANUFACTURING LOCATIONS ──────────────────────────────────────────
        db.execute(text("""
            INSERT INTO dim_manufacturing_location
                (location_name, country, city, nearest_shipping_port, lat, lng)
            VALUES
                ('Siemens Transformerwerk Hamburg',  'Germany',     'Hamburg',   'Port of Hamburg',    53.5753,  9.9928),
                ('CSSC Longxue Shipyard',            'China',       'Shanghai',  'Port of Shanghai',   30.8868, 121.8082),
                ('ABB Rotterdam Factory',            'Netherlands', 'Rotterdam', 'Port of Rotterdam',  51.9244,  4.4777),
                ('Hitachi Energy Yokohama',          'Japan',       'Yokohama',  'Port of Yokohama',   35.4437, 139.6380),
                ('Schneider Le Havre Plant',         'France',      'Le Havre',  'Port of Le Havre',   49.4944,  0.1079)
            ON CONFLICT DO NOTHING;
        """))
        print("✅ dim_manufacturing_location seeded")

        # ── 8. P6 SCHEDULE — the core risk data ────────────────────────────────
        # days_variance is a GENERATED column — do NOT insert it manually
        # It auto-computes as: forecast_finish - p6_schedule_due_date
        #
        # Scenario (from project context):
        #   EQ-001 Main Transformer  → 45 days late  → HIGH RISK
        #   EQ-006 Offshore Crane    → 60 days late  → HIGH RISK
        #   EQ-002 GIS Switchgear    → 20 days late  → MEDIUM RISK
        #   EQ-003 Diesel Generator  → 12 days late  → MEDIUM RISK
        #   EQ-004 MV Switchboard    →  3 days late  → LOW RISK
        #   EQ-005 Protection Panel  →  0 variance   → ON TRACK
        #   EQ-007 HV Cable System   →  0 variance   → ON TRACK
        #   EQ-008 Battery BESS      → -5 days early → EARLY
        db.execute(text("""
            INSERT INTO fact_p6_schedule
                (project_id, work_package_id, equipment_id, milestone_id,
                 p6_schedule_due_date, forecast_finish, percent_complete)
            VALUES
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-001'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-06-30', '2025-08-14', 35.00   -- 45 days late → HIGH RISK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-002'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-006'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-05-31', '2025-07-30', 20.00   -- 60 days late → HIGH RISK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-002'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-07-31', '2025-08-20', 50.00   -- 20 days late → MEDIUM RISK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-003'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-08-31', '2025-09-12', 60.00   -- 12 days late → MEDIUM RISK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-004'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-09-30', '2025-10-03', 70.00   -- 3 days late  → LOW RISK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-005'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-10-31', '2025-10-31', 80.00   -- 0 variance   → ON TRACK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-007'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-11-30', '2025-11-30', 40.00   -- 0 variance   → ON TRACK
                ),
                (
                    (SELECT project_id      FROM dim_project      WHERE project_code    = 'PRJ-001'),
                    (SELECT work_package_id FROM dim_work_package WHERE work_package_code = 'WP-001'),
                    (SELECT equipment_id    FROM dim_equipment    WHERE equipment_code  = 'EQ-008'),
                    (SELECT milestone_id    FROM dim_milestone    WHERE milestone_code  = 'MS-10'),
                    '2025-10-15', '2025-10-10', 55.00   -- -5 days      → EARLY
                );
        """))
        print("✅ fact_p6_schedule seeded (days_variance auto-computed by DB)")

        # ── COMMIT ALL ───────────────────────────────────────────────────────────
        db.commit()
        print("\n🎉 All seed data committed successfully!")

        # ── QUICK VERIFICATION ───────────────────────────────────────────────────
        result = db.execute(text("""
            SELECT
                e.equipment_code,
                e.equipment_name,
                s.days_variance,
                CASE
                    WHEN s.days_variance IS NULL     THEN 'NO FORECAST'
                    WHEN s.days_variance < 0          THEN 'EARLY'
                    WHEN s.days_variance = 0          THEN 'ON TRACK'
                    WHEN s.days_variance / NULLIF(
                        (s.p6_schedule_due_date - CURRENT_DATE), 0
                    )::FLOAT * 100 < 5               THEN 'LOW RISK'
                    WHEN s.days_variance / NULLIF(
                        (s.p6_schedule_due_date - CURRENT_DATE), 0
                    )::FLOAT * 100 < 15              THEN 'MEDIUM RISK'
                    ELSE                                  'HIGH RISK'
                END AS risk_category
            FROM fact_p6_schedule s
            JOIN dim_equipment    e ON s.equipment_id = e.equipment_id
            ORDER BY s.days_variance DESC NULLS LAST;
        """))
        rows = result.fetchall()
        print("\n📊 Schedule Risk Summary:")
        print(f"  {'Equipment':<30} {'Days Variance':>14} {'Risk':>12}")
        print(f"  {'-'*30} {'-'*14} {'-'*12}")
        for row in rows:
            variance_str = str(row[2]) if row[2] is not None else "N/A"
            print(f"  {row[1]:<30} {variance_str:>14} {row[3]:>12}")

    except Exception as e:
        db.rollback()
        print(f"\n❌ Seed failed: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    seed()
