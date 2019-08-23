-- This function weights the number of employees based on the cost that belongs to these employees.
-- For example:
-- If 100 employees have a low travel time (=cost) of nearly zero, they count as 100 employees.
-- If 100 employees have a very high travel time of e.g. 600 they will count as only ~20 employees.

CREATE OR REPLACE FUNCTION public.compute_weighted_audience(employees NUMERIC, cost NUMERIC) -- TODO: add population

RETURNS numeric
LANGUAGE plpgsql

AS $function$

DECLARE 
	weighted_audience NUMERIC;

BEGIN

	-- The function is configured so that at a travel time of 360 seconds, only half the people will visit the destination
	weighted_audience = employees * (1-(1/(1+power(EXP(1), (-0.015*(cost-360))))));
	RETURN weighted_audience;
	
END;
$function$;


--SELECT compute_weighted_audience(1, 600)