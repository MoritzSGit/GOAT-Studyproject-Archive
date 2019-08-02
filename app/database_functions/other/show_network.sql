CREATE OR REPLACE FUNCTION public.show_network(max_cost float,modus_input integer, userid_input integer)
 RETURNS TABLE(id bigint,node integer,cost NUMERIC,class_id integer, geom geometry)
 LANGUAGE plpgsql
AS $function$
DECLARE
--Declares the output as type pg_isochrone

ways_table varchar(20) := 'ways';
sql_userid varchar(100):='';
excluded_class_id varchar(200);
excluded_ways_id text;
column_userid varchar(10) :='';
categories_no_foot text; 
begin
  --depending on the modus the default OR the input table is used
  if modus_input = 2 OR modus_input = 4 then
  	ways_table = 'ways_userinput';
  	sql_userid = ' AND userid IS NULL OR userid ='||userid_input;
    column_userid = ', w.userid ';
  END IF;
 
  RAISE NOTICE '%',sql_userid;
  
  SELECT array_append(array_agg(x.id),0::bigint)::text INTO excluded_ways_id FROM (
	SELECT Unnest(deleted_feature_ids) id FROM user_data u
	WHERE u.id = userid_input
	UNION ALL
	SELECT original_id modified
	FROM ways_modified 
	WHERE userid = userid_input AND original_id IS NOT null
  ) x;
 
  SELECT variable_array::varchar(200)
  INTO excluded_class_id 
  FROM variable_container v
  WHERE v.identifier = 'excluded_class_id_walking';
 
  SELECT variable_array::text 
  INTO categories_no_foot
  FROM variable_container
  WHERE identifier = 'categories_no_foot';
 
  return query execute '
  with xx AS (
		SELECT * FROM (		--Select all that share ways that share a node with the edges
			SELECT w.id, n.node, w.source, w.target, w.geom, coalesce(w.class_id,0) class_id, n.cost'||column_userid||',foot 
			FROM '||ways_table||' w, temp_edges n 
			WHERE w.source = n.node
			OR w.target = n.node 
		) t 
		WHERE NOT t.class_id = ANY('''||excluded_class_id||''')
		AND (NOT foot = any('''||categories_no_foot||''') OR foot IS NULL)
		AND NOT t.id::int4 = any('''|| excluded_ways_id ||''')'
		||sql_userid||'
	),
	x AS (
		SELECT xx.*
		FROM xx, 
		(
			SELECT max(cost) AS cost, geom   
			FROM xx
			GROUP BY geom
			HAVING count(geom) > 1
			UNION ALL 
			SELECT max(cost) AS cost, geom   
			FROM xx 
			GROUP BY geom
			HAVING count(geom) = 1
		) t
		WHERE xx.geom = t.geom 
		AND xx.cost=t.cost
	),
	y AS ( --Select all that only share one node with the edges ==> these are lines touching at the borders
		SELECT count(*), SOURCE
		FROM 
		(	SELECT source FROM x
			UNION ALL
			SELECT target FROM x
		) x
		GROUP BY SOURCE 
		HAVING count(*) < 2
	),
	z AS ( -- Cut these touching lines depending on the value missing to reach isochrone calculation limit 
		SELECT x.id, x.node,'||max_cost||' AS cost, x.class_id, st_linesubstring(geom,1-('||max_cost||'-cost)/ST_length(geom::geography),1) geom 
		FROM x, y
		WHERE x.SOURCE = y.source 
		AND 1-('||max_cost||'-cost)/ST_length(geom::geography) BETWEEN 0 AND 1
		UNION ALL 
		SELECT id,x.node,'||max_cost||' AS cost, x.class_id, st_linesubstring(geom,0.0,('||max_cost||'-cost)/ST_length(geom::geography)) geom FROM x, y
		WHERE x.target = y.source 
		AND ('||max_cost||'-cost)/ST_length(geom::geography) BETWEEN 0 AND 1
	)
	SELECT DISTINCT x.id, x.node, x.cost, x.class_id, x.geom 
	FROM x 
	LEFT JOIN z ON x.id = z.id 
	WHERE z.id IS NULL
	UNION ALL 
	SELECT z.id, z.node, z.cost, z.class_id, z.geom  FROM z
	UNION ALL
	SELECT id, node, cost, class_id, geom FROM (
		SELECT w.id, n.node, n.cost, w.class_id, w.geom, foot
		FROM '||ways_table||' w, temp_edges n 
		WHERE  w.source = n.node
		AND w.target = n.node
	) t 
	WHERE NOT t.class_id = ANY('''||excluded_class_id||''')
	AND (NOT foot = any('''||categories_no_foot||''') OR foot IS NULL)';
--Workaround St_CollectionExtract AND filter all with length 0
  RETURN;
END ;
$function$