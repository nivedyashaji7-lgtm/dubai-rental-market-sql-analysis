# UAE Rental Market Analysis with SQL (MySQL)

A SQL project that takes a raw, messy dataset of 73,742 UAE rental listings, cleans it, rebuilds it as a small relational database, and answers business questions about rents in Dubai and other emirates.

## Business problem

A property analyst or renter wants to know: **which cities and areas are expensive, what is a "typical" rent, and what drives rent up** (furnishing, bedrooms, property type)? The raw data has missing values, duplicate listings, and extreme outliers, so it cannot be used for analysis as it is.

## Objectives

1. Load the raw CSV into MySQL and check that no rows were lost.
2. Profile and clean the data (missing values, zero rents, duplicates).
3. Redesign the flat file into related tables with primary and foreign keys.
4. Answer business questions with joins, aggregation, CTEs, window functions, and subqueries.
5. Turn the results into findings, and state their limits honestly.

## Dataset

- **Source:** dubai_properties
- **Size:** 73,742 listings, 17 columns
- **Coverage:** all UAE emirates (Dubai is the largest, with 34,250 raw listings). Listings are posted up to about 10 April 2024, mostly from late 2023.
- **Key columns:** `Address`, `Rent` (AED per year), `Beds`, `Baths`, `Type`, `Area_in_sqft`, `Rent_per_sqft`, `Furnishing`, `Posted_date`, `Location`, `City`, `Latitude`, `Longitude`

## Database design

| Table | Rows | Purpose |
|---|---|---|
| `raw_listings` | 73,742 | Untouched copy of the CSV (staging layer) |
| `listings_clean` | 73,503 | Cleaned working copy |
| `property_types` | 9 | Lookup: one row per property type |
| `locations` | 451 | Lookup: one row per location + city pair |
| `listings` | 73,503 | Main analysis table, linked to the two lookup tables by foreign keys |

```
property_types (type_id PK, type_name)
locations      (location_id PK, location_name, city)
listings       (listings_id PK, location_id FK, type_id FK, Rent, Beds, Baths, ...)
```

A location is identified by **name and city together**, because 10 location names exist in two different cities.

## Data cleaning

| Problem | How it was found | Fix |
|---|---|---|
| 719 rows skipped by the import | Row count (73,023) did not match the file (73,742) | Loaded coordinates as text in the staging table, then converted them to numbers |
| 719 empty coordinates | `WHERE Latitude = ''` | Set to `NULL`, converted columns to `DECIMAL` |
| 15 listings with `Rent = 0` | `WHERE Rent = 0` | Set rent, rent per sqft and category to `NULL` so they do not distort averages |
| 239 duplicate listings | `GROUP BY ... HAVING COUNT(*) > 1`, then `ROW_NUMBER()` | Deleted extra copies with a strict 8-column definition of a duplicate |

## SQL concepts used

`CREATE TABLE`, `INSERT ... SELECT`, `UPDATE`, `DELETE`, `ALTER TABLE`, `DISTINCT`, `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, aggregate functions (`COUNT`, `AVG`, `MIN`, `MAX`, `ROUND`), `INNER JOIN`, `LEFT JOIN`, primary and foreign keys, `CASE`, CTEs (including two in one query), window functions (`ROW_NUMBER`, `RANK`, `LAG`, `COUNT() OVER`), subqueries, `NULL` handling, date formatting (`DATE_FORMAT`).

## Business questions and findings

| # | Question | Finding |
|---|---|---|
| 1 | Which cities are the most expensive? | Dubai is highest (average about 213,000 AED/year), then Abu Dhabi (about 115,000). Sharjah is about 48,000 and Umm Al Quwain about 45,000. |
| 2 | What is the typical rent? | Dubai's **median is about 145,000**, far below its average. A few luxury listings pull the average up. In Umm Al Quwain the average is about 68% above the median. |
| 3 | Does furnishing change rent? | Furnished Dubai apartments average about **32% more** than unfurnished (182,658 vs 138,704), and about 32% more per sqft (164.5 vs 124.7). |
| 4 | How are Dubai rents spread? | Mid-priced (50k to 150k) is the biggest band at about 45% of listings. Premium is about 32%, Luxury about 17%, Budget about 6.5%. |
| 5 | How does property type affect rent? | 44 whole "Residential Building" listings average about 2.9M, against about 110k for 56,329 apartments, so buildings should not be averaged with homes. |
| 6 | How does rent change with bedrooms? | Rent per sqft rises with size, from about 137 for studios to about 202 for 4-bedroom apartments in Dubai. |
| 7 | Which Dubai areas are the most expensive per sqft? | Bluewaters Island (about 330), Dubai Harbour (about 227), Jumeirah (about 226), Downtown Dubai (about 197). |
| 8 | Top areas in every city | See query Q8. Fujairah and Umm Al Quwain have no area with 50+ apartment listings. |
| 9 | Monthly trend in Dubai | The monthly average fell from about 270,000 (Sep 2023) to about 185,000 (Apr 2024), but listings grew from 392 to 13,491 a month, so the mix changed. This is not evidence of falling prices. |
| 10 | Which areas beat the Dubai average per sqft? | 14 of 40 areas with 100+ listings are above the Dubai average of about 142.8 per sqft. |
| 11 | Which property types are missing in Fujairah? | Only apartments (16) and villas (11) are listed. The other 7 types have no listings. |

## Limitations

- **Small samples:** Fujairah (27 listings) and Umm Al Quwain (65) are too small for reliable averages.
- **Asking rents:** the data shows advertised rents, not signed contracts.
- **Time range:** data ends around 10 April 2024, so April is a partial month.
- **No listing ID:** duplicates were defined with a strict rule, so some real duplicates may remain.
- **Rare data errors:** a few rents (for example a rent of 1) are clearly wrong and were left in.
- **Correlation, not cause:** the furnished premium does not prove that furnishing raises rent. Furnished flats may also sit in pricier buildings.

## How to reproduce

1. Install MySQL 8.0 and MySQL Workbench.
2. Download the dataset and save it as `dubai_properties.csv`. Make sure `Posted_date` is in `YYYY-MM-DD` format.
3. Open `dubai_rental_project.sql` in Workbench and run Section 1.
4. Import the CSV into `raw_listings` with **Table Data Import Wizard** (use the existing table).
5. Check that `SELECT COUNT(*) FROM raw_listings;` returns 73,742.
6. Run Sections 2 to 5 in order. The checks inside the file tell you the expected numbers (73,503 clean rows, 451 locations, 9 types).

## Repository contents

- `dubai_rental_project.sql`: the full, commented script
- `README.md`: this file

## Author

**P S Nivedya**: [LinkedIn](https://www.linkedin.com/in/p-s-nivedya-703236354) | [GitHub](https://github.com/nivedyashaji7-lgtm)
