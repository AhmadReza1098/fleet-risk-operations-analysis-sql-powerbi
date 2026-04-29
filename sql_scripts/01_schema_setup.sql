/*
===============================================================================
Project: Fleet Risk & Operations Command Center
File: 01_schema_setup.sql
Description: 
This script defines the relational database schema for the enterprise fleet.
It establishes 14 core tables covering drivers, trucks, loads, trips, 
and maintenance, ensuring data integrity through Primary and Foreign Key constraints.
===============================================================================
*/

-- 1. DRIVERS
CREATE TABLE DRIVERS (
    driver_id TEXT PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    hire_date DATE,
    termination_date DATE,
    license_number TEXT,
    license_state TEXT,
    date_of_birth DATE,
    home_terminal TEXT,
    employment_status TEXT,
    cdl_class TEXT,
    years_experience INTEGER
);

-- 2. CUSTOMERS
CREATE TABLE CUSTOMERS (
    customer_id TEXT PRIMARY KEY,
    customer_name TEXT,
    customer_type TEXT,
    credit_terms_days INTEGER,
    primary_freight_type TEXT,
    account_status TEXT,
    contract_start_date DATE,
    annual_revenue_potential REAL
);

-- 3. FACILITIES
CREATE TABLE FACILITIES (
    facility_id TEXT PRIMARY KEY,
    facility_name TEXT,
    facility_type TEXT,
    city TEXT,
    state TEXT,
    latitude REAL,
    longitude REAL,
    dock_doors INTEGER,
    operating_hours TEXT
);

-- 4. ROUTES
CREATE TABLE ROUTES (
    route_id TEXT PRIMARY KEY,
    origin_city TEXT,
    origin_state TEXT,
    destination_city TEXT,
    destination_state TEXT,
    typical_distance_miles REAL,
    base_rate_per_mile REAL,
    fuel_surcharge_rate REAL,
    typical_transit_days INTEGER
);

-- 5. LOADS
CREATE TABLE LOADS (
    load_id TEXT PRIMARY KEY,
    customer_id TEXT,
    route_id TEXT,
    load_date DATE,
    load_type TEXT,
    weight_lbs REAL,
    pieces INTEGER,
    revenue REAL,
    fuel_surcharge REAL,
    accessorial_charges REAL,
    load_status TEXT,
    booking_type TEXT,
    FOREIGN KEY (customer_id) REFERENCES CUSTOMERS(customer_id),
    FOREIGN KEY (route_id) REFERENCES ROUTES(route_id)
);

-- 6. FUEL_PURCHASES
CREATE TABLE FUEL_PURCHASES (
    fuel_purchase_id TEXT PRIMARY KEY,
    trip_id TEXT,
    truck_id TEXT,
    driver_id TEXT,
    purchase_date DATE,
    location_city TEXT,
    location_state TEXT,
    gallons REAL,
    price_per_gallon REAL,
    total_cost REAL,
    fuel_card_number TEXT,
    FOREIGN KEY (driver_id) REFERENCES DRIVERS(driver_id)
);

-- 7. MAINTENANCE_RECORDS
CREATE TABLE MAINTENANCE_RECORDS (
    maintenance_id TEXT PRIMARY KEY,
    truck_id TEXT,
    maintenance_date DATE,
    maintenance_type TEXT,
    odometer_reading INTEGER,
    labor_hours REAL,
    labor_cost REAL,
    parts_cost REAL,
    total_cost REAL,
    facility_location TEXT,
    downtime_hours REAL,
    service_description TEXT
);

-- 8. DELIVERY_EVENTS
CREATE TABLE DELIVERY_EVENTS (
    event_id TEXT PRIMARY KEY,
    load_id TEXT,
    trip_id TEXT,
    event_type TEXT,
    facility_id TEXT,
    scheduled_datetime DATETIME,
    actual_datetime DATETIME,
    detention_minutes INTEGER,
    on_time_flag TEXT,
    location_city TEXT,
    location_state TEXT,
    FOREIGN KEY (load_id) REFERENCES LOADS(load_id),
    FOREIGN KEY (facility_id) REFERENCES FACILITIES(facility_id)
);

-- 9. SAFETY_INCIDENTS
CREATE TABLE SAFETY_INCIDENTS (
    incident_id TEXT PRIMARY KEY,
    trip_id TEXT,
    truck_id TEXT,
    driver_id TEXT,
    incident_date DATE,
    incident_type TEXT,
    location_city TEXT,
    location_state TEXT,
    at_fault_flag TEXT,
    injury_flag TEXT,
    vehicle_damage_cost REAL,
    cargo_damage_cost REAL,
    claim_amount REAL,
    preventable_flag TEXT,
    description TEXT,
    FOREIGN KEY (driver_id) REFERENCES DRIVERS(driver_id)
);

-- 10. DRIVER_MONTHLY_METRICS
CREATE TABLE DRIVER_MONTHLY_METRICS (
    driver_id TEXT,
    month TEXT,
    trips_completed INTEGER,
    total_miles REAL,
    total_revenue REAL,
    average_mpg REAL,
    total_fuel_gallons REAL,
    on_time_delivery_rate REAL,
    average_idle_hours REAL,
    PRIMARY KEY (driver_id, month),
    FOREIGN KEY (driver_id) REFERENCES DRIVERS(driver_id)
);

-- 11. TRAILERS
CREATE TABLE TRAILERS (
    trailer_id TEXT PRIMARY KEY,
    trailer_number TEXT,
    trailer_type TEXT,
    length_feet INTEGER,
    model_year INTEGER,
    vin TEXT,
    acquisition_date DATE,
    status TEXT,
    current_location TEXT
);

-- 12. TRUCKS (Final Version)
CREATE TABLE TRUCKS (
    truck_id TEXT PRIMARY KEY,
    unit_number TEXT,
    make TEXT,
    model_year INTEGER,
    vin TEXT,
    acquisition_date DATE,
    acquisition_mileage INTEGER,
    fuel_type TEXT,
    tank_capacity_gallons INTEGER,
    status TEXT,
    home_terminal TEXT
);

-- 13. TRIPS (The central link for your risk logic)
CREATE TABLE TRIPS (
    trip_id TEXT PRIMARY KEY,
    load_id TEXT,
    driver_id TEXT,
    truck_id TEXT,
    trailer_id TEXT,
    dispatch_date DATE,
    actual_distance_miles REAL,
    actual_duration_hours REAL,
    fuel_gallons_used REAL,
    average_mpg REAL,
    idle_time_hours REAL,
    trip_status TEXT,
    FOREIGN KEY (load_id) REFERENCES LOADS(load_id),
    FOREIGN KEY (driver_id) REFERENCES DRIVERS(driver_id),
    FOREIGN KEY (truck_id) REFERENCES TRUCKS(truck_id),
    FOREIGN KEY (trailer_id) REFERENCES TRAILERS(trailer_id)
);

-- 14. TRUCK_UTILIZATION_METRICS
CREATE TABLE TRUCK_UTILIZATION_METRICS (
    truck_id TEXT,
    month TEXT,
    trips_completed INTEGER,
    total_miles REAL,
    total_revenue REAL,
    average_mpg REAL,
    maintenance_events INTEGER,
    maintenance_cost REAL,
    downtime_hours REAL,
    utilization_rate REAL,
    PRIMARY KEY (truck_id, month),
    FOREIGN KEY (truck_id) REFERENCES TRUCKS(truck_id)
);