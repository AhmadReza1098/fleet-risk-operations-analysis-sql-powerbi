/*
===============================================================================
Project: Fleet Risk & Operations Command Center
File: 04_ad_hoc_analysis.sql
Description: 
This script contains both the finalized business queries used for the executive 
presentation (Section A) and the exploratory ad-hoc queries used during the 
initial data discovery phase (Section B).
===============================================================================
*/

-- ============================================================================
-- SECTION A: EXECUTIVE BUSINESS INSIGHTS
-- These queries answer the core questions outlined in the project README,
-- utilizing the optimized Views built in the 03_risk_aggregations script.
-- ============================================================================

-- QUESTION 1: Which top 5 customers are causing the highest margin leakage?
SELECT 
    customer_name,
    COUNT(load_id) AS total_loads,
    SUM(total_billed_revenue) AS total_revenue,
    SUM(normal_profit) AS total_margin,
    ROUND(SUM(normal_profit) / SUM(total_billed_revenue) * 100, 2) AS overall_margin_pct
FROM vw_powerbi_financial_risk
GROUP BY customer_name
ORDER BY total_margin ASC
LIMIT 5;

-- QUESTION 2: Which routes are hyper-sensitive to fuel price spikes?
SELECT 
    city_pair,
    COUNT(load_id) AS loads_on_route,
    ROUND(AVG(risk_sensitivity_pct), 2) AS avg_fuel_risk_pct
FROM vw_powerbi_financial_risk
WHERE risk_sensitivity_pct > 30.00
GROUP BY city_pair
ORDER BY avg_fuel_risk_pct DESC
LIMIT 10;

-- QUESTION 3: At what age does a truck cross the $50k maintenance threshold?
SELECT 
    truck_age,
    COUNT(truck_id) AS active_trucks,
    ROUND(AVG(lifetime_maintenance_spend), 2) AS avg_maintenance_spend,
    ROUND(AVG(lifetime_miles), 2) AS avg_lifetime_miles
FROM vw_powerbi_asset_lifecycle
GROUP BY truck_age
ORDER BY truck_age ASC;

-- QUESTION 4: Does driver tenure actually improve fleet efficiency?
SELECT 
    experience_bucket,
    COUNT(driver_id) AS total_drivers,
    ROUND(AVG(lifetime_avg_mpg), 2) AS group_avg_mpg,
    SUM(total_safety_incidents) AS total_accidents,
    ROUND(SUM(total_safety_incidents) / COUNT(driver_id), 2) AS accidents_per_driver
FROM vw_powerbi_human_risk
GROUP BY experience_bucket
ORDER BY experience_bucket ASC;


-- ============================================================================
-- SECTION B: EXPLORATORY DATA ANALYSIS (EDA) & AD-HOC QUERIES
-- The following queries were used during the data discovery phase to profile 
-- the dataset, identify anomalies, and shape the logic for the Power BI views.
-- ============================================================================

-- EDA 1: Original Margin Leakage Logic (Testing CTEs before View creation)
WITH Clean_Event_Logs AS (
    SELECT p.load_id 
    FROM DELIVERY_EVENTS p
    JOIN DELIVERY_EVENTS d ON p.load_id = d.load_id
    WHERE p.event_type = 'Pickup' 
      AND d.event_type = 'Delivery' 
      AND d.actual_datetime >= p.actual_datetime
),
Margin_Calculation AS (
    SELECT 
        l.load_id,
        l.route_id,
        l.customer_id,
        l.revenue,
        (t.fuel_gallons_used * 3.90) AS fuel_cost,
        (t.actual_distance_miles * 0.047) AS maintenance_provision,
        (l.revenue - (t.fuel_gallons_used * 3.90) - (t.actual_distance_miles * 0.047)) AS net_margin
    FROM LOADS l
    JOIN TRIPS t ON l.load_id = t.load_id
    JOIN Clean_Event_Logs cl ON l.load_id = cl.load_id
    WHERE t.trip_status = 'Completed'
),
Risk_Scoring AS (
    SELECT 
        *, 
        AVG(net_margin) OVER(PARTITION BY route_id) AS route_benchmark
    FROM Margin_Calculation
)
SELECT 
    c.customer_name,
    rs.route_id,
    ROUND(rs.net_margin) AS load_profit,
    ROUND(rs.route_benchmark) AS benchmark,
    ROUND(rs.net_margin - rs.route_benchmark, 2) AS variance,
    CASE
        WHEN (rs.net_margin - rs.route_benchmark) < -1200 THEN 'CRITICAL LEAKAGE'
        WHEN (rs.net_margin - rs.route_benchmark) < -600 THEN 'EROSION WATCHLIST'
        ELSE 'HEALTHY MARGIN'
    END AS risk_classification
FROM Risk_Scoring rs
JOIN CUSTOMERS c ON rs.customer_id = c.customer_id
ORDER BY variance ASC;


-- EDA 2: Original Fuel Price Shock Simulation (Pre-View logic)
WITH Fleet_Stats AS (
    SELECT
        AVG(price_per_gallon) AS avg_fuel,
        MAX(price_per_gallon) AS shock_fuel
    FROM FUEL_PURCHASES
),
Risk_Math AS (
    SELECT
        l.load_id,
        l.customer_id,
        l.revenue,
        t.fuel_gallons_used AS gallons,
        t.actual_distance_miles AS miles,
        (l.revenue - (t.fuel_gallons_used * (SELECT avg_fuel FROM Fleet_Stats)) - (t.actual_distance_miles * 0.047)) AS current_margin,
        (l.revenue - (t.fuel_gallons_used * (SELECT shock_fuel FROM Fleet_Stats)) - (t.actual_distance_miles * 0.047)) AS stressed_margin
    FROM LOADS l
    JOIN TRIPS t ON l.load_id = t.load_id
    WHERE trip_status = 'Completed'
)
SELECT 
    load_id,
    ROUND(current_margin, 2) AS normal_profit,
    ROUND(stressed_margin, 2) AS profit_after_shock,
    ROUND(current_margin - stressed_margin, 2) AS dollar_impact,
    ROUND(((current_margin - stressed_margin) / current_margin) * 100, 2) AS risk_sensitivity_pct
FROM Risk_Math
WHERE current_margin > 0 
ORDER BY risk_sensitivity_pct DESC;


-- EDA 3: Calculating True Fleet-Wide Maintenance Cost Per Mile (CPM)
SELECT 
    SUM(total_cost) AS total_spend,
    (SELECT SUM(actual_distance_miles) FROM TRIPS) AS total_miles,
    CAST(SUM(total_cost) AS FLOAT) / (SELECT SUM(actual_distance_miles) FROM TRIPS) AS actual_cpm
FROM MAINTENANCE_RECORDS;


-- EDA 4: Fuel Price Volatility (Arithmetic vs Geometric Mean)
SELECT 
    AVG(price_per_gallon) AS arithmetic_mean,
    EXP(AVG(LOG(price_per_gallon))) AS geometric_mean 
FROM FUEL_PURCHASES;


-- EDA 5: Original Asset Health & Safety Testing
WITH Maint_Total AS (
    SELECT truck_id, SUM(total_cost) AS truck_spend
    FROM MAINTENANCE_RECORDS
    GROUP BY truck_id
),
Miles_Total AS (
    SELECT truck_id, SUM(actual_distance_miles) AS truck_miles
    FROM TRIPS
    GROUP BY truck_id
)
SELECT 
    tr.truck_id,
    tr.make,
    tr.model_year,
    (2026 - tr.model_year) AS truck_age,
    m.truck_spend,
    mi.truck_miles,
    ROUND(CAST(m.truck_spend AS FLOAT) / NULLIF(mi.truck_miles, 0), 4) AS truck_cpm,
    CASE 
        WHEN (m.truck_spend / NULLIF(mi.truck_miles, 0)) > 0.07 THEN 'CRITICAL: High Maintenance'
        WHEN (m.truck_spend / NULLIF(mi.truck_miles, 0)) > 0.05 THEN 'WARNING: Above Average'
        ELSE 'EFFICIENT'
    END AS asset_health_status
FROM TRUCKS tr
JOIN Maint_Total m ON tr.truck_id = m.truck_id
JOIN Miles_Total mi ON tr.truck_id = mi.truck_id
ORDER BY truck_cpm DESC;


-- EDA 6: Do veteran drivers perform better than new hires? (Tenure vs Efficiency)
WITH Driver_Tenure AS (
    SELECT driver_id, (2026 - CAST(strftime('%Y', hire_date) AS INTEGER)) AS years_tenure
    FROM DRIVERS
),
OnTimes_Loads AS (
    SELECT 
        load_id,
        CASE WHEN actual_datetime <= scheduled_datetime THEN 1.0 ELSE 0.0 END AS is_on_time
    FROM DELIVERY_EVENTS d
    WHERE d.event_type = 'Delivery'
)
SELECT 
    dt.years_tenure,
    ROUND(SUM(t.actual_distance_miles) / NULLIF(SUM(t.fuel_gallons_used), 0), 2) AS avg_mpg,
    ROUND(AVG(ot.is_on_time) * 100, 2) AS on_time_pct
FROM Driver_Tenure dt
JOIN TRIPS t ON dt.driver_id = t.driver_id
LEFT JOIN OnTimes_Loads ot ON t.load_id = ot.load_id
GROUP BY dt.years_tenure
ORDER BY dt.years_tenure ASC;


-- EDA 7: How often should we send trucks to the shop to keep repair costs lowest?
WITH Maintenance_Gaps AS (
    SELECT 
        truck_id,
        odometer_reading,
        total_cost,
        odometer_reading - LAG(odometer_reading) OVER(PARTITION BY truck_id ORDER BY odometer_reading ASC) AS miles_since_last_service
    FROM MAINTENANCE_RECORDS
)
SELECT 
    CASE 
        WHEN miles_since_last_service < 10000 THEN '1. Under 10k miles'
        WHEN miles_since_last_service BETWEEN 10000 AND 20000 THEN '2. 10k - 20k miles'
        WHEN miles_since_last_service BETWEEN 20001 AND 30000 THEN '3. 20k - 30k miles'
        ELSE '4. Over 30k miles' 
    END AS service_interval,
    COUNT(*) AS number_of_services,
    ROUND(AVG(total_cost), 2) AS avg_cost_per_service
FROM Maintenance_Gaps
WHERE miles_since_last_service > 0 
GROUP BY service_interval
ORDER BY service_interval ASC;


-- EDA 8: Which customers are actually paying us the most every time we send a truck?
SELECT 
    c.customer_name,
    COUNT(l.load_id) AS total_loads,
    SUM(l.revenue) AS total_revenue,
    ROUND(SUM(l.revenue) / COUNT(l.load_id), 2) AS avg_revenue_per_load
FROM CUSTOMERS c
JOIN LOADS l ON c.customer_id = l.customer_id
GROUP BY c.customer_name
ORDER BY avg_revenue_per_load DESC
LIMIT 10;


-- EDA 9: What are the seasonal patterns in load volume and revenue?
SELECT 
    strftime('%m', load_date) AS order_month,
    COUNT(load_id) AS total_loads_moved,
    SUM(revenue) AS total_revenue
FROM LOADS
WHERE load_date IS NOT NULL
GROUP BY order_month
ORDER BY order_month ASC;


-- EDA 10: Who is crashing our trucks? Is it the new guys or the veterans?
WITH Driver_Tenure AS (
    SELECT driver_id, (2026 - CAST(strftime('%Y', hire_date) AS INTEGER)) AS years_tenure
    FROM DRIVERS
)
SELECT 
    CASE 
        WHEN years_tenure <= 3 THEN '1. Novice (0-3 yrs)'
        WHEN years_tenure <= 7 THEN '2. Intermediate (4-7 yrs)'
        WHEN years_tenure <= 12 THEN '3. Senior (8-12 yrs)'
        ELSE '4. Veteran (13+ yrs)' 
    END AS experience_bucket,
    COUNT(DISTINCT d.driver_id) AS total_drivers,
    COUNT(s.incident_id) AS total_incidents,
    ROUND(CAST(COUNT(s.incident_id) AS FLOAT) / COUNT(DISTINCT d.driver_id), 2) AS incident_rate_per_driver
FROM Driver_Tenure d
LEFT JOIN SAFETY_INCIDENTS s ON d.driver_id = s.driver_id
GROUP BY experience_bucket
ORDER BY experience_bucket ASC;


-- EDA 11: Which physical routes are almost impossible to complete on time?
WITH Delivery_Times AS (
    SELECT l.load_id, l.route_id, d.scheduled_datetime, d.actual_datetime
    FROM LOADS l
    JOIN DELIVERY_EVENTS d ON l.load_id = d.load_id
    WHERE d.event_type = 'Delivery'
)
SELECT 
    r.origin_city || ' to ' || r.destination_city AS city_pair,
    COUNT(dt.load_id) AS total_deliveries,
    SUM(CASE WHEN dt.actual_datetime <= dt.scheduled_datetime THEN 1 ELSE 0 END) AS on_time_count,
    ROUND(SUM(CASE WHEN dt.actual_datetime <= dt.scheduled_datetime THEN 1.0 ELSE 0.0 END) / COUNT(dt.load_id) * 100, 2) AS on_time_pct
FROM Delivery_Times dt
JOIN ROUTES r ON dt.route_id = r.route_id
GROUP BY city_pair
ORDER BY on_time_pct ASC
LIMIT 15;


-- EDA 12: How does truck age correlate with maintenance downtime?
SELECT 
    (2026 - t.model_year) AS truck_age,
    COUNT(DISTINCT t.truck_id) AS fleet_size,
    ROUND(AVG(m.total_cost), 2) AS avg_maintenance_cost,
    ROUND(AVG(m.downtime_hours), 2) AS avg_downtime_hours 
FROM TRUCKS t
JOIN MAINTENANCE_RECORDS m ON t.truck_id = m.truck_id
GROUP BY truck_age
ORDER BY truck_age ASC;


-- EDA 13: The Geographic Hub - Which terminals are the most expensive to run?
WITH Truck_Costs AS (
    SELECT 
        t.home_terminal, 
        t.truck_id, 
        SUM(m.total_cost) AS total_maint
    FROM TRUCKS t
    LEFT JOIN MAINTENANCE_RECORDS m ON t.truck_id = m.truck_id
    GROUP BY t.home_terminal, t.truck_id
)
SELECT 
    home_terminal,
    COUNT(truck_id) AS total_trucks_assigned,
    ROUND(AVG(total_maint), 2) AS avg_maint_cost_per_truck
FROM Truck_Costs
WHERE total_maint IS NOT NULL
GROUP BY home_terminal
ORDER BY avg_maint_cost_per_truck DESC;


-- EDA 14: ESG Initiative - How do different fuel types compare?
WITH Fuel_Efficiency AS (
    SELECT 
        t.truck_id,
        SUM(tr.actual_distance_miles) AS total_miles,
        SUM(tr.fuel_gallons_used) AS total_gallons
    FROM TRUCKS t
    JOIN TRIPS tr ON t.truck_id = tr.truck_id
    GROUP BY t.truck_id
),
Maint_Costs AS (
    SELECT 
        truck_id, 
        SUM(total_cost) AS life_maint_cost
    FROM MAINTENANCE_RECORDS
    GROUP BY truck_id
)
SELECT 
    t.fuel_type,
    COUNT(t.truck_id) AS fleet_size,
    ROUND(SUM(fe.total_miles) / NULLIF(SUM(fe.total_gallons), 0), 2) AS overall_mpg,
    ROUND(AVG(mc.life_maint_cost), 2) AS avg_lifetime_maint_cost
FROM TRUCKS t
LEFT JOIN Fuel_Efficiency fe ON t.truck_id = fe.truck_id
LEFT JOIN Maint_Costs mc ON t.truck_id = mc.truck_id
GROUP BY t.fuel_type
ORDER BY overall_mpg DESC;