/*
===============================================================================
Project: Fleet Risk & Operations Command Center
File: 02_data_cleaning.sql
Description: 
This script cleans the raw ingested data. It standardizes text fields, 
handles NULL values (financial imputation), and removes or flags operational 
anomalies (e.g., zero-mile trips, negative costs) before aggregation.
===============================================================================
*/

-- ============================================================================
-- 1. TEXT STANDARDIZATION & FORMATTING
-- Removing trailing spaces and ensuring consistent casing for joins and slicing
-- ============================================================================

-- Standardize Driver status and states
UPDATE DRIVERS 
SET employment_status = UPPER(TRIM(employment_status)),
    license_state = UPPER(TRIM(license_state));

-- Standardize Route state codes to 2 characters
UPDATE ROUTES
SET origin_state = UPPER(TRIM(origin_state)),
    destination_state = UPPER(TRIM(destination_state));

-- Standardize Customer names (removes accidental double spaces)
UPDATE CUSTOMERS
SET customer_name = TRIM(customer_name);


-- ============================================================================
-- 2. HANDLING NULLS & FINANCIAL IMPUTATION
-- Ensuring financial calculations in Power BI don't break due to NULL values
-- ============================================================================

-- If accessorial charges or fuel surcharges are NULL, set them to $0
UPDATE LOADS
SET fuel_surcharge = 0.0 WHERE fuel_surcharge IS NULL;

UPDATE LOADS
SET accessorial_charges = 0.0 WHERE accessorial_charges IS NULL;

-- If downtime hours in maintenance are missing, assume 0 to avoid skewing averages
UPDATE MAINTENANCE_RECORDS
SET downtime_hours = 0.0 WHERE downtime_hours IS NULL;


-- ============================================================================
-- 3. BUSINESS RULE ANOMALIES & OUTLIER HANDLING
-- Fixing impossible operational metrics (e.g., driving 0 miles using 50 gallons)
-- ============================================================================

-- Recalculate Average MPG for trips where it was improperly logged as 0 or NULL
-- Formula: MPG = Distance / Gallons Used (Ensure no division by zero)
UPDATE TRIPS
SET average_mpg = (actual_distance_miles / fuel_gallons_used)
WHERE (average_mpg IS NULL OR average_mpg <= 0)
  AND fuel_gallons_used > 0;

-- Flag impossible negative maintenance costs (likely data entry errors)
-- We set them to absolute values or NULL depending on business rules.
UPDATE MAINTENANCE_RECORDS
SET total_cost = ABS(total_cost)
WHERE total_cost < 0;

-- ============================================================================
-- 4. CREATE "CLEAN VIEWS" FOR POWER BI INGESTION
-- Instead of pointing Power BI to raw tables, we point it to these clean views
-- filtering out catastrophic errors (like Trips with no driver or truck).
-- ============================================================================

CREATE VIEW vw_clean_trips AS
SELECT 
    trip_id,
    load_id,
    driver_id,
    truck_id,
    dispatch_date,
    actual_distance_miles,
    actual_duration_hours,
    fuel_gallons_used,
    average_mpg,
    idle_time_hours
FROM TRIPS
-- Only pull valid trips into the dashboard
WHERE actual_distance_miles > 0 
  AND driver_id IS NOT NULL 
  AND truck_id IS NOT NULL;

DROP VIEW IF EXISTS vw_clean_loads;

CREATE VIEW vw_clean_loads AS
SELECT 
    load_id,
    customer_id,
    route_id,
    load_date,
    weight_lbs,
    revenue,
    fuel_surcharge, -- We added this missing column here!
    (revenue + fuel_surcharge + accessorial_charges) AS total_billed_revenue,
    load_status
FROM LOADS
WHERE revenue > 0;