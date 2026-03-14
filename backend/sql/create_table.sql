-- ================================================================
-- users
-- Required for JWT auth (FastAPI OAuth2 password flow).
-- Not in original (used Azure AD). You manage auth yourself.
-- ================================================================
CREATE TABLE users (
    user_id         SERIAL        PRIMARY KEY,
    username        VARCHAR(100)  UNIQUE NOT NULL,
    email           VARCHAR(255)  UNIQUE NOT NULL,
    hashed_password VARCHAR(255)  NOT NULL,
    role            VARCHAR(50)   NOT NULL DEFAULT 'expeditor',
                                           -- 'expeditor' | 'developer' | 'admin'
    is_active       BOOLEAN       DEFAULT TRUE,
    created_date    TIMESTAMP     DEFAULT NOW(),
    modified_date   TIMESTAMP     DEFAULT NOW()
);


 
-- ================================================================
-- TABLE 1 — dim_project
-- Top-level container. Every fact table links here.
-- Added vs original: receiving_port, project_city, client_name
-- ================================================================
CREATE TABLE dim_project (
    project_id       SERIAL          PRIMARY KEY,
    project_code     VARCHAR(20)     NOT NULL,
    project_name     VARCHAR(100)    NOT NULL,
    client_name      VARCHAR(255),
    project_country  VARCHAR(100),               -- destination country (for political/tariff agents)
    project_city     VARCHAR(100),
    receiving_port   VARCHAR(100),               -- LOGISTICS_RISK_AGENT uses this
    start_date       DATE,
    end_date         DATE,
    status           VARCHAR(20)     DEFAULT 'active',
                                                 -- 'active' | 'completed' | 'on_hold' | 'cancelled'
    created_date     TIMESTAMP       DEFAULT NOW(),
    modified_date    TIMESTAMP       DEFAULT NOW(),
    CONSTRAINT uq_project_code UNIQUE (project_code)
);


-- ================================================================
-- TABLE 2 — dim_equipment
-- Physical equipment items tracked through the supply chain.
-- Added vs original: criticality, hs_code, embedding
--   hs_code   → TARIFF_RISK_AGENT looks up tariff rates by HS code
--   embedding → pgvector semantic search ("find similar equipment")
-- ================================================================
CREATE TABLE dim_equipment (
    equipment_id     SERIAL          PRIMARY KEY,
    equipment_code   VARCHAR(20)     NOT NULL,
    equipment_name   VARCHAR(100)    NOT NULL,
    equipment_type   VARCHAR(50),               -- 'transformer' | 'switchgear' | 'generator'
    specifications   VARCHAR(500),
    criticality      VARCHAR(20)     DEFAULT 'medium',
                                                -- 'critical' | 'high' | 'medium' | 'low'
    lead_time_days   INTEGER,                   -- expected manufacturing + shipping time
    hs_code          VARCHAR(20),               -- Harmonized System code e.g. '8504.21'
                                                -- TARIFF_RISK_AGENT uses this for duty lookup
    embedding        vector(768),               -- Gemini text-embedding-004 dimensions
                                                -- enables: find equipment similar to description
    created_date     TIMESTAMP       DEFAULT NOW(),
    modified_date    TIMESTAMP       DEFAULT NOW(),
    CONSTRAINT uq_equipment_code UNIQUE (equipment_code)
);
 

-- ================================================================
-- TABLE 3 — dim_supplier
-- Vendor / manufacturer who makes and ships equipment.
-- Added vs original: country, region, shipping_port, risk_tier, embedding
--   shipping_port → LOGISTICS_RISK_AGENT uses this as origin port
--   risk_tier     → quick risk filter: 1=low, 2=medium, 3=high
--   embedding     → semantic search on supplier descriptions
-- ================================================================
CREATE TABLE dim_supplier (
    supplier_id      SERIAL          PRIMARY KEY,
    supplier_number  VARCHAR(20)     NOT NULL,
    supplier_name    VARCHAR(100)    NOT NULL,
    country          VARCHAR(100),              -- manufacturing country
                                                -- POLITICAL_RISK_AGENT + TARIFF_RISK_AGENT use this
    region           VARCHAR(100),              -- 'Europe' | 'Asia Pacific' | 'South Asia'
    city             VARCHAR(100),
    shipping_port    VARCHAR(100),              -- port of export
                                                -- LOGISTICS_RISK_AGENT uses this
    contact_name     VARCHAR(100),
    contact_number   VARCHAR(50),
    email_address    VARCHAR(100),
    risk_tier        INTEGER         DEFAULT 2, -- 1=low | 2=medium | 3=high
    embedding        vector(768),               -- semantic search on supplier profiles
    created_date     TIMESTAMP       DEFAULT NOW(),
    modified_date    TIMESTAMP       DEFAULT NOW(),
    CONSTRAINT uq_supplier_number UNIQUE (supplier_number)
);
 


-- ================================================================
-- TABLE 4 — dim_milestone
-- Lookup table for milestone types in the equipment lifecycle.
-- Added vs original: milestone_code, sequence_order
-- ================================================================
CREATE TABLE dim_milestone (
    milestone_id          SERIAL      PRIMARY KEY,
    milestone_code        VARCHAR(20),          -- e.g. 'MS-01', 'MS-04'
    milestone_activity    VARCHAR(100) NOT NULL, -- e.g. 'Factory Acceptance Test'
    milestone_description VARCHAR(255),
    milestone_type        VARCHAR(50),          -- 'design'|'manufacturing'|'inspection'|'shipping'|'delivery'
    sequence_order        INTEGER,              -- lifecycle order: 1=Design, 9=Site Delivery
    created_date          TIMESTAMP   DEFAULT NOW(),
    modified_date         TIMESTAMP   DEFAULT NOW(),
    CONSTRAINT uq_milestone_activity UNIQUE (milestone_activity, milestone_description)
);

 
-- ================================================================
-- TABLE 5 — dim_work_package
-- Groups equipment into logical work packages within a project.
-- Added vs original: project_id FK, status, start_date, end_date
-- ================================================================
CREATE TABLE dim_work_package (
    work_package_id   SERIAL         PRIMARY KEY,
    project_id        INTEGER        NOT NULL REFERENCES dim_project(project_id),
    work_package_code VARCHAR(20)    NOT NULL,
    work_package_name VARCHAR(100)   NOT NULL,
    wbs               VARCHAR(50),              -- WBS code from P6
    responsible_party VARCHAR(100),
    start_date        DATE,
    end_date          DATE,
    status            VARCHAR(20)    DEFAULT 'active',
    created_date      TIMESTAMP      DEFAULT NOW(),
    modified_date     TIMESTAMP      DEFAULT NOW(),
    CONSTRAINT uq_work_package_code UNIQUE (work_package_code)
);
 
-- ================================================================
-- TABLE 6 — dim_equipment_supplier  (bridge / junction table)
-- Links equipment to its suppliers (one equipment → many suppliers).
-- Changed vs original: is_preferred → is_primary (clearer naming)
-- One equipment can have a primary supplier + backup supplier(s).
-- ================================================================
CREATE TABLE dim_equipment_supplier (
    equipment_supplier_id  SERIAL       PRIMARY KEY,
    equipment_id           INTEGER      NOT NULL REFERENCES dim_equipment(equipment_id),
    supplier_id            INTEGER      NOT NULL REFERENCES dim_supplier(supplier_id),
    is_primary             BOOLEAN      DEFAULT TRUE,
                                                -- TRUE = primary supplier
                                                -- FALSE = backup / alternate supplier
    unit_cost              DECIMAL(18,2),
    currency               VARCHAR(10)  DEFAULT 'USD',
    lead_time_days         INTEGER,
    contract_number        VARCHAR(100),
    remarks                VARCHAR(500),
    created_date           TIMESTAMP    DEFAULT NOW(),
    modified_date          TIMESTAMP    DEFAULT NOW(),
    CONSTRAINT uq_equipment_supplier UNIQUE (equipment_id, supplier_id)
);
 

-- ================================================================
-- TABLE 7 — dim_manufacturing_location
-- WHERE equipment is physically manufactured.
-- RESTRUCTURED vs original:
--   Original had equipment_id + supplier_id FKs making it
--   an equipment-level record (duplicated per equipment).
--   Yours is a standalone location lookup — factories don't
--   change per equipment item. Equipment links via fact_purchase_order.
-- Added: lat, lng, risk scores (cached from agent runs)
-- ================================================================
CREATE TABLE dim_manufacturing_location (
    manufacturing_location_id  SERIAL        PRIMARY KEY,
    location_name              VARCHAR(255)  NOT NULL,
    country                    VARCHAR(100)  NOT NULL,  -- POLITICAL_RISK_AGENT + TARIFF_RISK_AGENT use this
    city                       VARCHAR(100),
    location_address           VARCHAR(255),
    nearest_shipping_port      VARCHAR(100),
    lat                        DECIMAL(10,7),
    lng                        DECIMAL(10,7),
    -- Cached risk scores — updated after each agent analysis run
    -- Avoids re-running full agent analysis for same location
    political_risk_score       DECIMAL(3,2),   -- 0.00 to 1.00
    tariff_risk_score          DECIMAL(3,2),   -- 0.00 to 1.00
    logistics_risk_score       DECIMAL(3,2),   -- 0.00 to 1.00
    last_risk_updated_at       TIMESTAMP,
    created_date               TIMESTAMP     DEFAULT NOW(),
    modified_date              TIMESTAMP     DEFAULT NOW()
);
 
-- ================================================================
-- TABLE 8 — dim_logistics_info
-- Shipping route details per equipment item.
-- LOGISTICS_RISK_AGENT extracts shipping_port + receiving_port
-- to build its Tavily search query.
-- Added vs original: incoterms, shipping_mode, estimated_transit_days
-- ================================================================
CREATE TABLE dim_logistics_info (
    logistics_info_id        SERIAL       PRIMARY KEY,
    equipment_id             INTEGER      NOT NULL REFERENCES dim_equipment(equipment_id),
    supplier_id              INTEGER      NOT NULL REFERENCES dim_supplier(supplier_id),
    logistics_method         VARCHAR(50)  NOT NULL,   -- 'sea' | 'air' | 'road' | 'rail'
    shipping_port            VARCHAR(100),            -- port of origin (export)
    receiving_port           VARCHAR(100),            -- port of destination (import)
    shipping_country         VARCHAR(100),
    receiving_country        VARCHAR(100),
    incoterms                VARCHAR(20),             -- 'FOB' | 'CIF' | 'DAP' | 'EXW'
    estimated_transit_days   INTEGER,
    freight_forwarder        VARCHAR(255),
    created_date             TIMESTAMP    DEFAULT NOW(),
    modified_date            TIMESTAMP    DEFAULT NOW()
);
 
-- ================================================================
-- TABLE 9 — fact_p6_schedule
-- P6 Primavera project schedule — planned vs forecast dates.
-- This is SCHEDULER_AGENT's primary data source.
-- Added vs original: forecast_finish, percent_complete, float_days,
--                    days_variance (GENERATED computed column)
--
-- SCHEDULER_AGENT risk formula:
--   risk_percent = days_variance / (p6_schedule_due_date - today) * 100
--   days_variance = forecast_finish - p6_schedule_due_date
-- ================================================================
CREATE TABLE fact_p6_schedule (
    p6_schedule_id       SERIAL       PRIMARY KEY,
    project_id           INTEGER      NOT NULL REFERENCES dim_project(project_id),
    work_package_id      INTEGER      NOT NULL REFERENCES dim_work_package(work_package_id),
    equipment_id         INTEGER      NOT NULL REFERENCES dim_equipment(equipment_id),
    milestone_id         INTEGER      NOT NULL REFERENCES dim_milestone(milestone_id),
    -- Baseline (never changes after project start)
    p6_schedule_due_date DATE         NOT NULL,  -- original planned finish date
    -- Current forecast (updated as project progresses)
    actual_start         DATE,
    forecast_finish      DATE,                   -- current best estimate for finish
    actual_finish        DATE,                   -- filled when milestone is actually complete
    percent_complete     DECIMAL(5,2) DEFAULT 0.00,
    float_days           INTEGER      DEFAULT 0, -- schedule buffer / slack
    -- Computed column: positive = LATE, negative = EARLY, 0 = ON TRACK
    -- Auto-calculated by DB — no manual update needed
    days_variance        INTEGER GENERATED ALWAYS AS (
                             CASE
                               WHEN forecast_finish IS NOT NULL
                               THEN (forecast_finish - p6_schedule_due_date)::INTEGER
                               ELSE NULL
                             END
                         ) STORED,
    created_date         TIMESTAMP    DEFAULT NOW(),
    modified_date        TIMESTAMP    DEFAULT NOW()
);

-- ================================================================
-- TABLE 10 — fact_purchase_order
-- PO records: the commercial link between project, supplier, equipment.
-- Added vs original: delivery_date_forecast, manufacturing_location_id
-- ================================================================
CREATE TABLE fact_purchase_order (
    purchase_order_id       SERIAL          PRIMARY KEY,
    purchase_order_number   VARCHAR(50)     NOT NULL,
    line_item               VARCHAR(20),
    project_id              INTEGER         NOT NULL REFERENCES dim_project(project_id),
    work_package_id         INTEGER         NOT NULL REFERENCES dim_work_package(work_package_id),
    supplier_id             INTEGER         NOT NULL REFERENCES dim_supplier(supplier_id),
    equipment_id            INTEGER         NOT NULL REFERENCES dim_equipment(equipment_id),
    manufacturing_location_id INTEGER       REFERENCES dim_manufacturing_location(manufacturing_location_id),
    short_text              VARCHAR(255),
    amount                  DECIMAL(18,2),
    currency                VARCHAR(10)     DEFAULT 'USD',
    po_date                 DATE,
    delivery_date_promised  DATE,           -- contractual date from supplier
    delivery_date_forecast  DATE,           -- supplier's latest forecast (updated regularly)
    delivery_date_actual    DATE,           -- filled when equipment physically arrives
    status                  VARCHAR(20)     DEFAULT 'open',
                                            -- 'draft'|'open'|'in_production'|'shipped'|'delivered'|'cancelled'
    remarks                 VARCHAR(500),
    created_date            TIMESTAMP       DEFAULT NOW(),
    modified_date           TIMESTAMP       DEFAULT NOW(),
    CONSTRAINT uq_po_number_line UNIQUE (purchase_order_number, line_item)
);

-- ================================================================
-- TABLE 11 — fact_equipment_milestone_schedule
-- Granular milestone tracking per equipment item.
-- More detailed than fact_p6_schedule — one row per milestone per equipment.
-- Added vs original: forecast_date, delay_days (GENERATED), status
-- ================================================================
CREATE TABLE fact_equipment_milestone_schedule (
    equipment_milestone_id   SERIAL      PRIMARY KEY,
    equipment_id             INTEGER     NOT NULL REFERENCES dim_equipment(equipment_id),
    project_id               INTEGER     NOT NULL REFERENCES dim_project(project_id),
    work_package_id          INTEGER     NOT NULL REFERENCES dim_work_package(work_package_id),
    milestone_id             INTEGER     NOT NULL REFERENCES dim_milestone(milestone_id),
    purchase_order_id        INTEGER     REFERENCES fact_purchase_order(purchase_order_id),
    -- Dates
    equipment_milestone_due_date  DATE   NOT NULL,  -- planned date
    forecast_date            DATE,                  -- current forecast
    actual_date              DATE,                  -- actual completion
    -- Computed: positive = LATE, negative = EARLY
    delay_days               INTEGER GENERATED ALWAYS AS (
                                 CASE
                                   WHEN forecast_date IS NOT NULL
                                   THEN (forecast_date - equipment_milestone_due_date)::INTEGER
                                   WHEN actual_date IS NOT NULL
                                   THEN (actual_date - equipment_milestone_due_date)::INTEGER
                                   ELSE NULL
                                 END
                             ) STORED,
    status                   VARCHAR(20) DEFAULT 'pending',
                                                -- 'pending'|'in_progress'|'completed'|'delayed'|'at_risk'
    created_date             TIMESTAMP   DEFAULT NOW(),
    modified_date            TIMESTAMP   DEFAULT NOW()
);

-- ================================================================
-- TABLE 12 — dim_agent_session
-- NEW — not in original RiskWise.
-- One row per user conversation / full analysis run.
-- Tracks the complete lifecycle of a multi-agent workflow.
-- Replaces what was scattered across dim_agent_thinking_log rows.
--
-- Why this is better than the original:
--   Original: 20-28 rows in dim_agent_thinking_log per query,
--             no single "this run" summary row.
--   Yours: 1 clean summary row per run + link to LangSmith trace
--          for full details.
-- ================================================================
CREATE TABLE dim_agent_session (
    session_id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             INTEGER       REFERENCES users(user_id),
    project_id          INTEGER       REFERENCES dim_project(project_id),
    -- What was asked
    query_text          TEXT,                       -- original user message
    query_type          VARCHAR(100),               -- 'schedule_risk' | 'political_risk'
                                                    -- 'tariff_risk' | 'logistics_risk' | 'full_analysis'
    -- Which agents ran
    agents_invoked      TEXT[],                     -- ARRAY['SCHEDULER_AGENT','POLITICAL_RISK_AGENT']
    -- Lifecycle
    status              VARCHAR(20)   DEFAULT 'running',
                                                    -- 'running' | 'completed' | 'failed' | 'partial'
    started_at          TIMESTAMP     DEFAULT NOW(),
    completed_at        TIMESTAMP,
    total_duration_ms   INTEGER,
    -- LangSmith link — click this to see full agent trace with all thinking steps
    langsmith_run_id    TEXT,
    langsmith_trace_url TEXT,
    -- Error tracking
    error_message       TEXT,
    created_date        TIMESTAMP     DEFAULT NOW()
);


-- ================================================================
-- TABLE 13 — dim_agent_event_log
-- SLIMMED DOWN vs original.
-- Original stored full agent_output (entire response text) here.
-- Yours stores session-level events only — what happened, not what was thought.
-- Full reasoning traces → LangSmith (automatic, zero extra code).
--
-- What to store here:
--   agent_name='SCHEDULER_AGENT', event_type='analysis_complete'
--   agent_name='POLITICAL_RISK_AGENT', event_type='search_complete'
--   agent_name='REPORTING_AGENT', event_type='report_saved'
--
-- What NOT to store (goes to LangSmith automatically):
--   "I am now reviewing the data..."
--   Every intermediate thinking step
-- ================================================================
CREATE TABLE dim_agent_event_log (
    log_id        SERIAL        PRIMARY KEY,
    session_id    UUID          NOT NULL,           -- links to dim_agent_session
    agent_name    VARCHAR(100)  NOT NULL,
                                                    -- 'SCHEDULER_AGENT' | 'POLITICAL_RISK_AGENT'
                                                    -- 'TARIFF_RISK_AGENT' | 'LOGISTICS_RISK_AGENT'
                                                    -- 'REPORTING_AGENT' | 'ASSISTANT_AGENT'
    event_type    VARCHAR(100)  NOT NULL,
                                                    -- 'agent_started' | 'tool_called' | 'tool_result'
                                                    -- 'analysis_complete' | 'search_complete'
                                                    -- 'report_saved' | 'agent_error' | 'handoff'
    event_data    JSONB,                            -- structured payload, queryable
                                                    -- e.g. {"tool": "tavily_search", "results": 7}
                                                    -- e.g. {"risk_counts": {"high":2,"medium":3}}
                                                    -- e.g. {"s3_key": "reports/2025/...", "filename": "..."}
    duration_ms   INTEGER,                          -- how long this event took
    success       BOOLEAN       DEFAULT TRUE,
    error_detail  TEXT,                             -- filled only if success=FALSE
    created_date  TIMESTAMP     DEFAULT NOW()
);
 
-- ================================================================
-- TABLE 14 — fact_risk_report
-- REDESIGNED vs original.
-- Original stored only: session_id, filename, blob_url
-- Yours stores: full structured JSON per agent + langsmith_run_id
-- 
-- Why JSONB per agent:
--   You can query: WHERE political_risk_json @> '{"risk_level": "high"}'
--   You can extract: political_risk_json->>'overall_score'
--   The frontend can render each agent's section independently.
-- ================================================================
CREATE TABLE fact_risk_report (
    report_id              SERIAL        PRIMARY KEY,
    session_id             UUID          NOT NULL,
    project_id             INTEGER       REFERENCES dim_project(project_id),
    -- Structured JSON output from each agent
    -- JSONB = binary JSON: indexed, queryable with ->> and @> operators
    schedule_risk_json     JSONB,                   -- from SCHEDULER_AGENT
    political_risk_json    JSONB,                   -- from POLITICAL_RISK_AGENT
    tariff_risk_json       JSONB,                   -- from TARIFF_RISK_AGENT
    logistics_risk_json    JSONB,                   -- from LOGISTICS_RISK_AGENT
    -- Aggregate summary
    overall_risk_score     DECIMAL(4,2),            -- 0.00 to 10.00
    risk_level             VARCHAR(20),             -- 'low' | 'medium' | 'high' | 'critical'
    high_risk_count        INTEGER       DEFAULT 0,
    medium_risk_count      INTEGER       DEFAULT 0,
    low_risk_count         INTEGER       DEFAULT 0,
    -- File output
    filename               VARCHAR(255),            -- report filename
    blob_url               TEXT,                    -- S3 presigned URL or key
    report_s3_key          TEXT,                    -- permanent S3 object key
    -- Observability: paste langsmith_run_id into smith.langchain.com to see full trace
    langsmith_run_id       TEXT,
    generated_by_agents    TEXT[],                  -- which agents contributed
    created_date           TIMESTAMP     DEFAULT NOW()
);

