/* =====================================================================
   UAE / DUBAI RENTAL MARKET ANALYSIS  |  MySQL 8.0
   Author : P S Nivedya
   Purpose: Clean a raw rental-listings dataset, build a small relational
            database, and answer business questions with SQL.

   HOW TO USE
   - Run the sections in order, on a NEW database.
   - Section 2 needs the CSV import step (Workbench: Table Data Import
     Wizard -> Use existing table -> raw_listings).
   - Do not run Sections 1 to 5 again on a database that is already built.
   ===================================================================== */


/* =====================================================================
   SECTION 1: DATABASE AND RAW (STAGING) TABLE
   The raw table keeps the data exactly as it came in the CSV.
   Latitude and Longitude are TEXT here because 719 rows have empty
   coordinates, and the import wizard skips rows that cannot fit a number.
   ===================================================================== */
CREATE DATABASE IF NOT EXISTS dubai_rental_db;
USE dubai_rental_db;

CREATE TABLE raw_listings (
    Address                 VARCHAR(150),
    Rent                    INT,
    Beds                    INT,
    Baths                   INT,
    Type                    VARCHAR(30),
    Area_in_sqft            INT,
    Rent_per_sqft           DECIMAL(10,2),
    Rent_category           VARCHAR(20),
    Frequency               VARCHAR(20),
    Furnishing              VARCHAR(20),
    Purpose                 VARCHAR(20),
    Posted_date             DATE,
    Age_of_listing_in_days  INT,
    Location                VARCHAR(50),
    City                    VARCHAR(30),
    Latitude                VARCHAR(30),
    Longitude               VARCHAR(30)
);

/* >>> IMPORT dubai_properties.csv HERE (Table Data Import Wizard) <<< */

-- Check 1: row count must match the CSV (73,742 rows)
SELECT COUNT(*) AS raw_rows FROM raw_listings;


/* =====================================================================
   SECTION 2: DATA PROFILING (look before you clean)
   ===================================================================== */

-- Listings per city
SELECT City, COUNT(*) AS total
FROM raw_listings
GROUP BY City
ORDER BY total DESC;

-- Listings with a rent of zero (expect 15)
SELECT COUNT(*) AS zero_rent_rows
FROM raw_listings
WHERE Rent = 0;

-- Empty coordinates are stored as '' (expect 719)
SELECT COUNT(*) AS empty_latitude
FROM raw_listings
WHERE Latitude = '';


/* =====================================================================
   SECTION 3: DATA CLEANING (done on a copy, raw table stays untouched)
   ===================================================================== */
CREATE TABLE listings_clean AS
SELECT * FROM raw_listings;

SET SQL_SAFE_UPDATES = 0;   -- allow UPDATE/DELETE with a WHERE on non-key columns

-- 3.1 Empty coordinates -> NULL, then convert the columns to numbers
UPDATE listings_clean
SET Latitude = NULL, Longitude = NULL
WHERE Latitude = '' AND Longitude = '';

ALTER TABLE listings_clean
    MODIFY Latitude  DECIMAL(12,8),
    MODIFY Longitude DECIMAL(12,8);

-- 3.2 Rent = 0 means "rent not entered": set it (and the values built from it) to NULL
UPDATE listings_clean
SET Rent = NULL,
    Rent_per_sqft = NULL,
    Rent_category = NULL
WHERE Rent = 0;

-- 3.3 Duplicates. The data has no listing ID, so a duplicate is defined strictly:
--     same address, rent, beds, baths, type, area, furnishing AND posted date.
--     First add a unique ID so one copy can be kept and the others deleted.
ALTER TABLE listings_clean
    ADD COLUMN listing_id INT AUTO_INCREMENT PRIMARY KEY FIRST;

-- Count the extra copies first (expect 239)
WITH numbered AS (
    SELECT listing_id,
           ROW_NUMBER() OVER (
               PARTITION BY Address, Rent, Beds, Baths, Type, Area_in_sqft, Furnishing, Posted_date
               ORDER BY listing_id
           ) AS copy_no
    FROM listings_clean
)
SELECT COUNT(*) AS extra_copies
FROM numbered
WHERE copy_no > 1;

-- Delete only copies 2, 3, ... and keep copy 1 of every group
WITH numbered AS (
    SELECT listing_id,
           ROW_NUMBER() OVER (
               PARTITION BY Address, Rent, Beds, Baths, Type, Area_in_sqft, Furnishing, Posted_date
               ORDER BY listing_id
           ) AS copy_no
    FROM listings_clean
)
DELETE FROM listings_clean
WHERE listing_id IN (
    SELECT listing_id FROM numbered WHERE copy_no > 1
);

-- Check 2: expect 73,503 rows (73,742 minus 239)
SELECT COUNT(*) AS clean_rows FROM listings_clean;


/* =====================================================================
   SECTION 4: DATA MODELLING (lookup tables + main table with foreign keys)
   ===================================================================== */

-- 4.1 Property types: one row per type
CREATE TABLE property_types (
    type_id   INT AUTO_INCREMENT PRIMARY KEY,
    type_name VARCHAR(30)
);

INSERT INTO property_types (type_name)
SELECT DISTINCT Type FROM listings_clean;          -- expect 9 rows

-- 4.2 Locations: one row per (location, city) pair.
--     The pair is needed because some location names exist in two cities.
CREATE TABLE locations (
    location_id   INT AUTO_INCREMENT PRIMARY KEY,
    location_name VARCHAR(50),
    city          VARCHAR(30)
);

INSERT INTO locations (location_name, city)
SELECT DISTINCT Location, City FROM listings_clean;   -- expect 451 rows

-- Location names that appear in more than one city (expect 10)
SELECT location_name, COUNT(*) AS cities_count
FROM locations
GROUP BY location_name
HAVING COUNT(*) > 1;

-- 4.3 Main analysis table. Frequency and Purpose are left out because every
--     row has the same value (Yearly / For Rent).
CREATE TABLE listings (
    listings_id            INT PRIMARY KEY,
    location_id            INT,
    type_id                INT,
    Address                VARCHAR(150),
    Rent                   INT,
    Beds                   INT,
    Baths                  INT,
    Area_in_sqft           INT,
    Rent_per_sqft          DECIMAL(10,2),
    Rent_category          VARCHAR(20),
    Furnishing             VARCHAR(20),
    Posted_date            DATE,
    Age_of_listing_in_days INT,
    Latitude               DECIMAL(12,8),
    Longitude              DECIMAL(12,8),
    FOREIGN KEY (location_id) REFERENCES locations(location_id),
    FOREIGN KEY (type_id)     REFERENCES property_types(type_id)
);

INSERT INTO listings (
    listings_id, location_id, type_id, Address, Rent, Beds, Baths,
    Area_in_sqft, Rent_per_sqft, Rent_category, Furnishing,
    Posted_date, Age_of_listing_in_days, Latitude, Longitude
)
SELECT
    l.listing_id, loc.location_id, pt.type_id, l.Address, l.Rent, l.Beds, l.Baths,
    l.Area_in_sqft, l.Rent_per_sqft, l.Rent_category, l.Furnishing,
    l.Posted_date, l.Age_of_listing_in_days, l.Latitude, l.Longitude
FROM listings_clean l
INNER JOIN locations loc
        ON l.Location = loc.location_name AND l.City = loc.city
INNER JOIN property_types pt
        ON l.Type = pt.type_name;

-- Check 3: expect 73,503 rows and 15 listings with no rent
SELECT COUNT(*) AS listings_rows FROM listings;
SELECT COUNT(*) AS null_rent_rows FROM listings WHERE Rent IS NULL;


/* =====================================================================
   SECTION 5: BUSINESS ANALYSIS
   ===================================================================== */

/* ---- Q1. Which cities are the most expensive? (average rent) ---- */
SELECT loc.city,
       COUNT(*) AS total_listings,
       ROUND(AVG(l.Rent), 0) AS avg_rent
FROM listings l
INNER JOIN locations loc ON l.location_id = loc.location_id
GROUP BY loc.city
ORDER BY avg_rent DESC;


/* ---- Q2. What is the typical rent per city? (median) ----
   MySQL has no MEDIAN(), so rows are numbered inside each city and the
   middle row (or the two middle rows) is averaged. */
WITH ranked AS (
    SELECT loc.city,
           l.Rent,
           ROW_NUMBER() OVER (PARTITION BY loc.city ORDER BY l.Rent) AS rn,
           COUNT(*)     OVER (PARTITION BY loc.city)                 AS cnt
    FROM listings l
    INNER JOIN locations loc ON l.location_id = loc.location_id
    WHERE l.Rent IS NOT NULL
)
SELECT city,
       ROUND(AVG(Rent), 0) AS median_rent
FROM ranked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY city
ORDER BY median_rent DESC;


/* ---- Q3. Does furnishing change the rent? (Dubai apartments only) ---- */
SELECT l.Furnishing,
       COUNT(l.Rent) AS total_listings,
       ROUND(AVG(l.Rent), 0) AS avg_rent,
       ROUND(AVG(l.Rent_per_sqft), 1) AS avg_rent_per_sqft
FROM listings l
INNER JOIN locations loc ON l.location_id = loc.location_id
INNER JOIN property_types pt ON l.type_id = pt.type_id
WHERE loc.city = 'Dubai' AND pt.type_name = 'Apartment'
GROUP BY l.Furnishing;


/* ---- Q4. How are Dubai rents spread across price bands? (CASE) ---- */
SELECT CASE
           WHEN l.Rent < 50000  THEN 'Budget'
           WHEN l.Rent < 150000 THEN 'Mid'
           WHEN l.Rent < 300000 THEN 'Premium'
           ELSE 'Luxury'
       END AS rent_band,
       COUNT(*) AS total_listings,
       ROUND(AVG(l.Rent), 0) AS avg_rent
FROM listings l
INNER JOIN locations loc ON l.location_id = loc.location_id
WHERE loc.city = 'Dubai' AND l.Rent IS NOT NULL
GROUP BY rent_band
ORDER BY MIN(l.Rent);


/* ---- Q5. How does rent differ by property type? (spot outliers) ---- */
SELECT pt.type_name,
       COUNT(l.Rent) AS total_listings,
       ROUND(AVG(l.Rent), 0) AS avg_rent,
       MIN(l.Rent) AS min_rent,
       MAX(l.Rent) AS max_rent
FROM listings l
INNER JOIN property_types pt ON l.type_id = pt.type_id
GROUP BY pt.type_name
ORDER BY avg_rent DESC;


/* ---- Q6. How does rent change with bedrooms? (Dubai apartments; 0 = studio) ---- */
SELECT l.Beds,
       COUNT(l.Rent) AS total_listings,
       ROUND(AVG(l.Rent), 0) AS avg_rent,
       ROUND(AVG(l.Rent_per_sqft), 1) AS avg_rent_per_sqft
FROM listings l
INNER JOIN locations loc ON l.location_id = loc.location_id
INNER JOIN property_types pt ON l.type_id = pt.type_id
WHERE loc.city = 'Dubai' AND pt.type_name = 'Apartment'
GROUP BY l.Beds
ORDER BY l.Beds;


/* ---- Q7. Which Dubai areas are the most expensive per sqft? ----
   Areas with fewer than 100 listings are removed (HAVING) so a few odd
   listings cannot create a fake "top area". */
SELECT loc.location_name,
       COUNT(l.Rent) AS total_listings,
       ROUND(AVG(l.Rent_per_sqft), 1) AS avg_rent_per_sqft
FROM listings l
INNER JOIN locations loc ON l.location_id = loc.location_id
INNER JOIN property_types pt ON l.type_id = pt.type_id
WHERE loc.city = 'Dubai' AND pt.type_name = 'Apartment'
GROUP BY loc.location_name
HAVING COUNT(l.Rent) >= 100
ORDER BY avg_rent_per_sqft DESC
LIMIT 10;


/* ---- Q8. Top 3 most expensive areas in every city (window function RANK) ---- */
WITH location_stats AS (
    SELECT loc.city,
           loc.location_name,
           COUNT(l.Rent) AS total_listings,
           ROUND(AVG(l.Rent_per_sqft), 1) AS avg_psf
    FROM listings l
    INNER JOIN locations loc ON l.location_id = loc.location_id
    INNER JOIN property_types pt ON l.type_id = pt.type_id
    WHERE pt.type_name = 'Apartment'
    GROUP BY loc.city, loc.location_name
    HAVING COUNT(l.Rent) >= 50
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY city ORDER BY avg_psf DESC) AS rnk
    FROM location_stats
)
SELECT city, location_name, total_listings, avg_psf, rnk
FROM ranked
WHERE rnk <= 3
ORDER BY city, rnk;


/* ---- Q9. Monthly average rent in Dubai with month-over-month change (LAG) ----
   Starts in Sep 2023 because earlier months have very few listings.
   April 2024 is a partial month (data ends around 10 April). */
WITH monthly AS (
    SELECT DATE_FORMAT(l.Posted_date, '%Y-%m') AS rent_month,
           COUNT(l.Rent) AS total_listings,
           ROUND(AVG(l.Rent), 0) AS avg_rent
    FROM listings l
    INNER JOIN locations loc ON l.location_id = loc.location_id
    WHERE loc.city = 'Dubai'
      AND l.Posted_date >= '2023-09-01'
    GROUP BY rent_month
)
SELECT rent_month,
       total_listings,
       avg_rent,
       LAG(avg_rent) OVER (ORDER BY rent_month) AS prev_avg_rent,
       ROUND((avg_rent - LAG(avg_rent) OVER (ORDER BY rent_month))
             / LAG(avg_rent) OVER (ORDER BY rent_month) * 100, 1) AS pct_change
FROM monthly
ORDER BY rent_month;


/* ---- Q10. Which Dubai areas are above the Dubai average per sqft? (subquery) ---- */
SELECT loc.location_name,
       COUNT(l.Rent) AS total_listings,
       ROUND(AVG(l.Rent_per_sqft), 1) AS avg_rent_per_sqft
FROM listings l
INNER JOIN locations loc ON l.location_id = loc.location_id
INNER JOIN property_types pt ON l.type_id = pt.type_id
WHERE loc.city = 'Dubai' AND pt.type_name = 'Apartment'
GROUP BY loc.location_name
HAVING COUNT(l.Rent) >= 100
   AND AVG(l.Rent_per_sqft) > (
        SELECT AVG(l2.Rent_per_sqft)
        FROM listings l2
        INNER JOIN locations loc2 ON l2.location_id = loc2.location_id
        INNER JOIN property_types pt2 ON l2.type_id = pt2.type_id
        WHERE loc2.city = 'Dubai' AND pt2.type_name = 'Apartment'
   )
ORDER BY avg_rent_per_sqft DESC;


/* ---- Q11. Which property types have no listings in Fujairah? (LEFT JOIN) ----
   The city filter is in the ON clause. In WHERE it would remove the zero rows
   and turn the LEFT JOIN into an INNER JOIN. */
SELECT pt.type_name,
       COUNT(l.listings_id) AS fujairah_listings
FROM property_types pt
LEFT JOIN listings l
       ON l.type_id = pt.type_id
      AND l.location_id IN (SELECT location_id
                            FROM locations
                            WHERE city = 'Fujairah')
GROUP BY pt.type_name
ORDER BY fujairah_listings DESC;
