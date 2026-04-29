
/*
===============================================================================
Project: Fleet Risk & Operations Command Center
File: 03_risk_aggregations.sql
Description: 
This script creates highly optimized, aggregated views designed specifically 
for Power BI ingestion. It pre-calculates margin leakage, asset lifecycles, 
and human capital risk, significantly reducing DAX processing time in the BI layer.
===============================================================================
*/

-- ============================================================================
-- PAGE 1 & 2: FINANCIAL RISK & MARGIN LEAKAGE
-- Pre-joining clean loads, routes, and customers to calculate profit at risk.
-- ============================================================================

CREATE VIEW vw_powerbi_financial_risk AS
SELECT 
    l.load_id,
    c.customer_name,
    r.route_id,
    r.origin_city || ' to ' || r.destination_city AS city_pair,
    l.total_billed_revenue,
    -- Calculate Baseline Costs (Distance * Base Rate)
    (r.typical_distance_miles * r.base_rate_per_mile) AS projected_base_cost,
    -- Calculate Margin
    (l.total_billed_revenue - (r.typical_distance_miles * r.base_rate_per_mile)) AS normal_profit,
    -- Risk Metric: How sensitive is this load to fuel spikes?
    ROUND((l.fuel_surcharge / NULLIF(l.total_billed_revenue, 0)) * 100, 2) AS risk_sensitivity_pct
FROM vw_clean_loads l
JOIN CUSTOMERS c ON l.customer_id = c.customer_id
JOIN ROUTES r ON l.route_id = r.route_id;

-- ============================================================================
-- PAGE 3 (TOP): ASSET LIFECYCLE & MAINTENANCE BURDEN
-- Aggregating total maintenance spend and miles by truck to find the retirement "Sweet Spot".
-- ============================================================================

CREATE VIEW vw_powerbi_asset_lifecycle AS
SELECT 
    t.truck_id,
    t.make,
    -- Calculate current truck age
    (strftime('%Y', 'now') - t.model_year) AS truck_age,
    SUM(m.total_miles) AS lifetime_miles,
    SUM(m.maintenance_cost) AS lifetime_maintenance_spend,
    -- Create the Categorical Flag for the Dashboard's Red/Green formatting
    CASE 
        WHEN SUM(m.maintenance_cost) > 50000 THEN 'WARNING: Above Average'
        WHEN SUM(m.maintenance_cost) BETWEEN 25000 AND 50000 THEN 'MONITOR: Average'
        ELSE 'EFFICIENT'
    END AS asset_health_status
FROM TRUCKS t
JOIN TRUCK_UTILIZATION_METRICS m ON t.truck_id = m.truck_id
GROUP BY 
    t.truck_id, 
    t.make, 
    t.model_year;


-- ============================================================================
-- PAGE 3 (BOTTOM): HUMAN CAPITAL RISK
-- Correlating driver experience with safety incidents and operational efficiency.
-- ============================================================================

CREATE VIEW vw_powerbi_human_risk AS
SELECT 
    d.driver_id,
    (d.first_name || ' ' || d.last_name) AS driver_name,
    d.years_experience AS years_tenure,
    -- Experience Buckets for the Heatmap
    CASE 
        WHEN d.years_experience < 4 THEN '1. Rookie (0-3 yrs)'
        WHEN d.years_experience BETWEEN 4 AND 7 THEN '2. Intermediate (4-7 yrs)'
        WHEN d.years_experience BETWEEN 8 AND 12 THEN '3. Senior (8-12 yrs)'
        ELSE '4. Veteran (13+ yrs)'
    END AS experience_bucket,
    -- Averages across their monthly metrics
    AVG(dm.average_mpg) AS lifetime_avg_mpg,
    AVG(dm.on_time_delivery_rate) AS lifetime_on_time_pct,
    -- Count total safety incidents per driver
    COUNT(s.incident_id) AS total_safety_incidents
FROM DRIVERS d
JOIN DRIVER_MONTHLY_METRICS dm ON d.driver_id = dm.driver_id
LEFT JOIN SAFETY_INCIDENTS s ON d.driver_id = s.driver_id
GROUP BY 
    d.driver_id, 
    d.first_name, 
    d.last_name, 
    d.years_experience;
