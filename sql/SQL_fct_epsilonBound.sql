-- =================================================================================
-- Copyright 2014 Wolfgang Gatterbauer, Stephan Guennemann, Danai Koutra, Christos Faloutsos
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--     http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- =================================================================================
-- =================================================================================
-- Provides function fct_epsilonBound(A_tableName,H_tableName);
-- Calculates the max eps_H according to our guarantees for convergence of LinBP
-- Wolfgang Gatterbauer
-- First version: 6/4/2014
-- This version: 6/24/2014
--
-- Execute with: select * from fct_epsilonBound('a_kron1_7','h_kron');
-- Execute with: select max_esp1 from fct_epsilonBound('a_kron1_7','h_kron');
--		
-- Creates intermediate table D_temp
--
-- Returns array (see below)
-- =================================================================================


-- drop function fct_epsilonBound(varchar, varchar)
CREATE OR REPLACE FUNCTION fct_epsilonBound(
	A_tableName varchar, 
	H_tableName varchar)

RETURNS TABLE (	
	A_normV double precision, 	-- vector p=2 (Frobenius) norm
	A_normI double precision, 	-- induced p=1 & inf norm
	H_normV double precision, 
	H_normI double precision, 
	max_eps1 double precision, 		-- LinBP* without second order term
	max_eps2 double precision) as	-- LinBP with second order term
	
$BODY$

DECLARE
	A_normV double precision; 
	A_normI double precision; 	
	A_normMin double precision; 		
	H_normV double precision; 
	H_normI double precision; 	
	H_normMin double precision; 		
	D_norm double precision; 		
	max_eps1 double precision;
	max_eps2 double precision;	

BEGIN


-- Calculate exact D_norm from bi-directional degree matrix D (allowing direction and weight)
drop table if exists D_temp cascade;
EXECUTE 'create table D_temp as
select 	A1.s as v, 
		sum(A1.w*A2.w) as degree
from ' || A_tableName || '  A1, ' || A_tableName || '  A2
where A1.t = A2.s
and A1.s = A2.t
group by A1.s';

select max (degree)
into D_norm
from D_temp;


-- Vector p=2 (Frobenius) norms for A and H
execute'
select sqrt(sum(w^2))
from ' || A_tableName ||' '
into A_normV;

execute'
select sqrt(sum(h^2))
from ' || H_tableName ||' '
into H_normV;



-- Smaller of induced p=1 and p=infty norms for A and H
execute'
select min(n)
from (	
	select max(w) n
	from(	
		select sum(w) w
		from ' || A_tableName ||'
		group by s
		) as X
	union all
	select max(w) n
	from(	
		select sum(w) w
		from ' || A_tableName ||'
		group by t
		) as Y
	) as Z'
into A_normI;

execute'
select min(n)
from (	
	select max(h) n
	from(	
		select sum(@h) h
		from ' || H_tableName ||'
		group by c1
		) as X
	union all
	select max(h) n
	from(	
		select sum(@h) h
		from ' || H_tableName ||'
		group by c2
		) as Y
	) as Z'
into H_normI;



-- Choose smaller norms (Vector or induced) and calculate max_esp
A_normMin = least(A_normV, A_normI);
H_normMin = least(H_normV, H_normI);

max_eps1 =  1/H_normMin/A_normMin;
max_eps2 = (sqrt(A_normMin^2 + 4*D_norm)-A_normMin)/2/D_norm/H_normMin;

return query select 
	A_normV,
	A_normI,
	H_normV,
	H_normI,
	max_eps1,
	max_eps2;

END;
$BODY$
LANGUAGE plpgsql;


