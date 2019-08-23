DROP FUNCTION closest_employees(NUMERIC);
CREATE OR REPLACE FUNCTION closest_employees(snap_distance NUMERIC)
RETURNS SETOF jsonb[]
 LANGUAGE plpgsql
AS $function$

BEGIN 
	
	DROP TABLE IF EXISTS pois_and_pt;

	--pois_and_pt table that contains pois (id, amenity, name and geometry) inside the isochrone plus all public transport inside the isochrone
	
	CREATE TEMP TABLE employees_inside_isochrone AS 
	SELECT e.employees_adjusted, e.company_name, e.amenity, e.geom, e.id
	FROM employees e, isochrone i
	WHERE st_intersects(e.geom, i.geom);


	ALTER TABLE employees_inside_isochrone ADD PRIMARY key(id);
	CREATE INDEX ON employees_inside_isochrone USING gist(geom);
	
	RETURN query
	WITH distance_employees as (
		SELECT e.amenity, e.company_name, e.geom, vertices.COST, e.employees_adjusted
		FROM
		employees_inside_isochrone e
		CROSS JOIN LATERAL
	  	(SELECT geom, cost
	   	FROM temp_extrapolated_reached_vertices t
		WHERE t.geom && ST_Buffer(e.geom, snap_distance)
	   	ORDER BY
	    e.geom <-> t.geom
	   	LIMIT 1) AS vertices
	),

	
	key_value AS 
	(
		SELECT jsonb_build_object('company_name', company_name, 'cost', COST, 'audience', employees_adjusted, 'amenity', amenity) AS emps
		FROM distance_employees
		
	)
	SELECT array_agg(emps)
	FROM key_value
	;

DROP TABLE IF EXISTS employees_inside_isochrone;
	
END 
$function$;

