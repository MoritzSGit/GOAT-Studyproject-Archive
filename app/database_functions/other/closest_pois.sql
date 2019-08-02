CREATE OR REPLACE FUNCTION closest_pois(snap_distance NUMERIC)
RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$

BEGIN 
	
	DROP TABLE IF EXISTS pois_and_pt;
	CREATE temp TABLE pois_and_pt AS 
	SELECT p.gid as poi_gid,p.amenity,p.name, p.geom  
	FROM pois p,variable_container v, isochrone b 
	WHERE v.identifier = 'poi_categories'
	AND amenity = any(variable_array)
	AND st_intersects(p.geom, b.geom)
	UNION ALL 
	SELECT p.gid as poi_gid,public_transport_stop AS amenity,p.name,p.geom
	FROM public_transport_stops p, isochrone b
	WHERE st_intersects(p.geom,b.geom);

	ALTER TABLE pois_and_pt ADD PRIMARY key(poi_gid);
	CREATE INDEX ON pois_and_pt USING gist(geom);
	
	RETURN query 
	WITH distance_pois as (
		SELECT p.amenity, p.name, p.geom, vertices.cost
		FROM
		pois_and_pt p
		CROSS JOIN LATERAL
	  	(SELECT geom, cost
	   	FROM temp_extrapolated_reached_vertices t
		WHERE t.geom && ST_Buffer(p.geom,snap_distance)
	   	ORDER BY
	    p.geom <-> t.geom
	   	LIMIT 1) AS vertices
	),
	key_value AS 
	(
		SELECT jsonb_build_object(amenity,cost) AS pois
		FROM
		(
			SELECT amenity, array_agg(cost) AS cost 
			FROM 
			(
				SELECT amenity,min(cost) as cost FROM distance_pois --Every entrance OR bus_stop is only counted once (shortest distance is taken)
				WHERE amenity = ANY (ARRAY['subway_entrance','bus_stop','tram_stop','sbahn_regional'])
				GROUP BY amenity,name
			) x
			GROUP BY amenity
			UNION ALL
			SELECT amenity,array_agg(cost) FROM distance_pois
			WHERE amenity != ANY (ARRAY['subway_entrance','bus_stop','tram_stop','sbahn_regional'])
			GROUP BY amenity
		)x
	)
	SELECT regexp_replace(array_agg((pois))::text,
	    '}"(,)"{|\\| |^{"|"}$', 
	    '\1', 
	    'g'
	)::jsonb
	FROM key_value
	;
	
END 
$function$;