-- what we need as Input: A table called employees.
-- The table MUST contain these columns:
	-- geom::geometry - point geometry representing the location
	-- name::text - name of the company
	-- beschäfti::int - number of persons registered to work for this company
	-- standortin::text - the type of the location (headquarters, multi-branch, single-branch, store, ...) TODO: customize by user

--Optional:
	--employees_adjusted: if the user knows the exact number of employees for a specific point, they can set it and it will not be overwritten.

--What the script does: it adjusts the number of employees, because usually not all workers who are registered at a place actually work there.
-- E.g. 10000 workers are registered at a company's headquarters, but not all work at the headquarters.



ALTER TABLE employees ADD COLUMN IF NOT EXISTS employees_adjusted FLOAT;

-- set a no_auto_adjust flag on points for which the user has already specified an adjusted number of employees
ALTER TABLE employees ADD COLUMN IF NOT EXISTS no_auto_adjust BOOLEAN;
UPDATE employees
SET no_auto_adjust = TRUE
FROM employees
WHERE employees.employees_adjusted IS NOT NULL;


-- first it creates a table of employees that are considered save employees.
DROP TABLE IF EXISTS employees_save;
CREATE TABLE employees_save as
SELECT distinct e.*
FROM employees e
WHERE NOT((e.standortin = 'Konzernsitz' OR
		   e.standortin = 'Mehrbetriebsunternehmen')
	   AND e.beschäfti > (SELECT variable_simple::integer FROM variable_container WHERE identifier = 'save_employees_cutoff'))
 ORDER BY e.beschäfti DESC;
 
 
 -- next it creates a table of unsave employees
DROP TABLE IF EXISTS employees_unsave;
CREATE TABLE employees_unsave as
SELECT distinct e.*
 FROM employees e
 WHERE ((e.standortin = 'Konzernsitz' OR
			 e.standortin = 'Mehrbetriebsunternehmen')
			 AND e.beschäfti > (SELECT variable_simple::integer FROM variable_container WHERE identifier = 'save_employees_cutoff'))
 ORDER BY e.beschäfti DESC;

 
CREATE INDEX index_employees_save ON employees_save  USING GIST (geom);
CREATE INDEX index_employees_unsave ON employees_unsave USING GIST (geom);

 ------------------------------------------------------------------------------------------
------------------create table of buildings that only house save employees-----------------
-------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS all_buildings;
CREATE TABLE all_buildings AS
SELECT osm_id,building, "addr:housenumber",tags,way as geom
FROM planet_osm_polygon 
WHERE building IS NOT NULL;
CREATE INDEX index_all_buildings ON all_buildings  USING GIST (geom);

DROP TABLE IF EXISTS potentially_save_buildings;
CREATE TABLE potentially_save_buildings AS			--Get all buildings that house save employees 
	SELECT DISTINCT a_b.*
	FROM all_buildings a_b, employees_save e_s
	WHERE st_contains(a_b.geom, e_s.geom);
CREATE INDEX index_potentially_save_buildings ON potentially_save_buildings  USING GIST (geom);

DROP TABLE IF EXISTS buildings_save;					--remove buildings that also house unsave employees
CREATE TABLE buildings_save AS
	SELECT DISTINCT sb.*
	FROM 
	potentially_save_buildings AS sb LEFT JOIN
	employees_unsave AS es ON
	ST_Intersects(es.geom, sb.geom)
	WHERE es.id IS NULL;
CREATE INDEX index_buildings_save ON buildings_save  USING GIST (geom);	


DROP TABLE IF EXISTS potentially_save_buildings;

------------------------------------------------------------------------------------------
------------------calculate the area per employee for these buildings---------------------
------------------------------------------------------------------------------------------
ALTER TABLE buildings_save ADD COLUMN IF NOT EXISTS area_per_employee FLOAT;
ALTER TABLE buildings_save ADD COLUMN IF NOT EXISTS area FLOAT;
ALTER TABLE buildings_save ADD COLUMN IF NOT EXISTS sum_employees FLOAT;

UPDATE buildings_save SET
	sum_employees = (
		SELECT s.sum
		FROM (
			SELECT
			buildings_save.osm_id,
			buildings_save.geom,
			coalesce(sum(employees_save.beschäfti), -1) AS sum
			FROM buildings_save  
				LEFT JOIN employees_save
				ON ST_Intersects(buildings_save.geom, employees_save.geom) 
				GROUP BY buildings_save.osm_id, buildings_save.geom, buildings_save.area
				ORDER BY sum DESC
		) s
		WHERE s.osm_id = buildings_save.osm_id);

UPDATE buildings_save SET
	area = st_area(buildings_save.geom::geography);

UPDATE buildings_save SET
	area_per_employee = area/sum_employees
		WHERE sum_employees > 0;

DROP TABLE IF EXISTS employees_save;
------------------------------------------------------------------------------------------
------------------create table of buildings that house unsave_employees-------------------
------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS buildings_unsave;
CREATE TABLE buildings_unsave AS
 	SELECT DISTINCT all_buildings.*
 	FROM all_buildings, employees_unsave
 	WHERE st_contains(all_buildings.geom, employees_unsave.geom);
 
ALTER TABLE buildings_unsave ADD COLUMN IF NOT EXISTS area FLOAT;
UPDATE buildings_unsave
SET area = st_area(buildings_unsave.geom::geography);
DROP TABLE IF EXISTS all_buildings;

------------------------------------------------------------------------------------------
------------------get median of area per employee for save employees----------------------
------------------------------------------------------------------------------------------
 DROP TABLE IF EXISTS median;
CREATE TABLE median AS 
	SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY area_per_employee)
	FROM buildings_save;
DROP TABLE IF EXISTS buildings_save;
	

------------------------------------------------------------------------------------------
-------------adjust number of unsave employees according to area per employee ratio-------
------------------------------------------------------------------------------------------
ALTER TABLE employees_unsave ADD COLUMN IF NOT EXISTS area FLOAT;
UPDATE employees_unsave
SET area = (
	SELECT st_area(buildings_unsave.geom::geography)
	FROM buildings_unsave
	WHERE st_contains(buildings_unsave.geom, employees_unsave.geom));

ALTER TABLE employees_unsave ADD COLUMN IF NOT EXISTS employees_adjusted FLOAT;
UPDATE employees_unsave
SET employees_adjusted = area/median.percentile_disc
FROM median;
DROP TABLE IF EXISTS median;
DROP TABLE IF EXISTS buildings_unsave;
------------------------------------------------------------------------------------------
-------------put number of adjusted employees into original employees table.-------
-------------keep possible manual entries for employees_adjusted----------------
------------------------------------------------------------------------------------------

UPDATE employees
SET employees_adjusted = employees_unsave.employees_adjusted
FROM employees_unsave
WHERE employees.employees_adjusted IS NULL AND employees_unsave.id = employees.id;

UPDATE employees
SET employees_adjusted = employees.beschäfti
WHERE employees.employees_adjusted IS NULL;

DROP TABLE IF EXISTS employees_unsave;