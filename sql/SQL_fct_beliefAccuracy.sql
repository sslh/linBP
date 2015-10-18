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
-- Provides function fct_beliefAccuracy(B_tableGT varchar, B_tableOther varchar);
-- Returns 5 Statistics for calculating precision and recall
-- Wolfgang Gatterbauer
-- First version: 6/4/2014
-- This version: 6/28/2014
--
-- Execute with: select * from fct_beliefAccuracy('B_LinBP_5percent','B_SBP_5percent');
--
-- Additional change: top beliefs that are = 0 are discarded as they are not meaningful
-- =================================================================================



-- drop function fct_beliefAccuracy(varchar, varchar);
CREATE OR REPLACE FUNCTION fct_beliefAccuracy(B_tableGT varchar, B_tableOther varchar)	
RETURNS TABLE(
	n_GT_max int, 
	n_GT_unique int, 
	n_Other_max int, 
	n_Other_unique int, 
	n_Both int) as
	
$BODY$

DECLARE
	n_GT_max int; 			-- for GT: how many max beliefs (can include more one class for each node)
	n_GT_unique int;		-- for GT: how many different nodes
	n_Other_max int;
	n_Other_unique int;	
	n_Both int;				-- how many common top classes
	
BEGIN


-- Statistics for GT
drop table IF EXISTS B_tableGT_top;
EXECUTE 'create table B_tableGT_top as	
(select B.v, B.c, B.b
from '|| B_tableGT ||' B,
	(select B2.v, max(B2.b) as b
	from '|| B_tableGT ||' B2
	group by B2.v) as X
where B.v = X.v
and B.b = X.b);';	

select count(*)
into n_GT_max
from B_tableGT_top
where B_tableGT_top.b !=0;		-- ignore 0 assignments

select count(DISTINCT v)
into n_GT_unique
from B_tableGT_top;


-- Statistics for Other
drop table IF EXISTS B_tableOther_top;
EXECUTE 'create table B_tableOther_top as	
(select B.v, B.c, B.b
from '|| B_tableOther ||' B,
	(select B2.v, max(B2.b) as b
	from '|| B_tableOther ||' B2
	group by B2.v) as X
where B.v = X.v
and B.b = X.b);';	

select count(*)
into n_Other_max
from B_tableOther_top
where B_tableOther_top.b !=0;	-- ignore 0 assignments

select count(DISTINCT v)
into n_Other_unique
from B_tableOther_top;


-- Statistics for Both
select count(*)
into n_Both
from B_tableOther_top B1, B_tableGT_top B2
where B1.v = B2.v
and B1.c = B2.c;


return query select 
	n_GT_max,
	n_GT_unique,
	n_Other_max,
	n_Other_unique,
	n_Both;

END;
$BODY$
LANGUAGE plpgsql;






