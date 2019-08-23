CREATE OR REPLACE FUNCTION public.compute_audience_index(audience jsonb[])
-- This function takes an array of jsonb objects and computes a single numeric score value for the reached audience.
-- Each jsonb object belongs to the same cell in the heatmap and represents a specific point we can reach from the center.
-- The point holds the following information: cost and reached_employees.
-- based on these two values, we calculate an weighted audience value for each point.
-- We sum up all weighted audience values to get an index which is specific for the cell that belongs to the jsonb array.


--The jsonB must contain the following information:

-- "audience": numeric	<- the number of persons that can reach the cell center from a specific starting point
-- "cost": numeric 		<- the cost that it takes the persons to reach the cell center from a specific starting point.


RETURNS numeric
LANGUAGE plpgsql

AS $function$

DECLARE 
	sum_index NUMERIC;

BEGIN
	-- This is a table of jsonBs. it represents all points reached from one cell. This belongs into the compute_index function.
	-- It turns an array of jsonb into a table. 
	WITH all_infos AS 
	(
		SELECT unnest(audience) AS infos
	),
	
	-- this is a table of columns cost and employees
	infos AS
	(
		SELECT (infos ->> 'cost')::numeric AS cost, (infos ->> 'audience')::numeric AS reached_audience
		FROM all_infos
	),
	
	weighted_audience AS
	(
		SELECT compute_weighted_audience(reached_audience, cost) AS value
		FROM infos
	)
	
	SELECT sum(value) INTO sum_index
	FROM weighted_audience; 
	
	
	RETURN sum_index;
	
	
END 
$function$;

-----------------------------fill in employees column-----------------------------------------------
----------------------------------------------------------------------------------------------------
--Done via python script.
----------------------------------------------------------------------------------------------------



------------------calculate audience index based on employees column--------------------------------
----------------------------------------------------------------------------------------------------
--ALTER TABLE grid_500 ADD COLUMN audience_index_employees NUMERIC;
--UPDATE grid_500 set audience_index_employees = compute_audience_index(grid_500.employees)
--WHERE grid_id >= 10
----------------------------------------------------------------------------------------------------




