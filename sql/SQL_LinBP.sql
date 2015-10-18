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
-- Provides function LinBP('A','E','H',esp_H,maxIterations,'comment', approxOption, convergenceRatio, debugMode);
-- Calculates the final beliefs for LinBP
-- First version: 11/29/2013,
-- This version: 6/28/2014
-- Wolfgang Gatterbauer, Stephan Guennemann
--
-- Execute with: SELECT LinBP('a_kron1_7','e_kron1_7_5p','h_kron',0.0005,10,'comment', 2,0.0005,0);
-- 
-- Parameters		
-- 		maxIterations: maximal number of iterations (may stop earlier, depending on convergenceRatio)
-- 		approxOption int: if 2: LinBP with second order term, if 1: without 								
-- 		convergenceRatio: if 0: then iterates until maxIterations, 
-- 						  if >0: iterates until max(relative belief change) < convergenceRatio
-- 
-- Creates following tables fresh (deletes if exists)
-- 		D
--  	H: from H_input and eps_H
--		H2: squared H
--		B_LinBP: outcome, contains final beliefs
-- 
-- Creates and deletes following temporary tables inside the loop
-- 		B_0, B_1, B_2, ...
-- 		V1_1, V1_2, ... 
-- 		V2_1, V2_2, ... 
-- =================================================================================


-- DROP FUNCTION LinBP(varchar, varchar, varchar, double precision, int, varchar, int, double precision, int);
CREATE OR REPLACE FUNCTION LinBP(	
	A_input varchar, 
	E_input varchar, 
	H_input varchar, 
	eps_H double precision, 
	maxIterations int,					-- maximal number of iterations before function stops
	comment varchar,
	approxOption int,		 			-- 2: with second order term and D, 1: without 								
	convergenceRatio double precision,	-- 0: iterates until maxIterations
										-- >0: iterates until max(relative belief change) < convergenceRatio
	debugMode int)						-- 1: debug mode: save results in TimingTable, 0: does not
										
RETURNS TABLE(	
	timeLS int, 
	iterations int, 
	num_nodesExplicit int,	
	num_nodesAffected int,		-- how many nodes were affected in the process (implicit + explicit)	
	num_nodesImplicit int,		-- how many nodes have beliefs at the end (implicit + explicit)
	num_nodesTotal int,			-- number of nodes in graph
	numEdges int) as


$BODY$

DECLARE
	V_1 varchar;		-- two views
	V_2 varchar;
	B_new varchar;
	B_old varchar;
  	startTime timestamptz;
	endTime timestamptz;
	timeLs int;
	i int;
	
	n_B_old int;		-- number of beliefs in old belief table
	n_B_new int;		-- number of beliefs in new belief table
	diff_max double precision; -- max(relative belief change)
	
	num_nodesExplicit int;	-- count number of nodes with explicit beliefs
	num_nodesImplicit int;	-- count number of nodes affected by this run
	num_nodesTotal int;		-- count number of nodes
	num_edges int; 			-- number of edges in A
	
BEGIN


-- Create degree matrix D (allowing direction and weight)
drop table if exists D cascade;
EXECUTE 'create table D as
select 	A1.s as v, 
		sum(A1.w*A2.w) as degree
from ' || A_input || '  A1, ' || A_input || '  A2
where A1.t = A2.s
and A1.s = A2.t
group by A1.s';

-- Create table H using eps_H
drop table if exists H cascade;
EXECUTE 'create table H as
select 	horig.c1 as c1, 
		horig.c2 as c2,
		horig.h*$1 as h 
from ' || H_input ||  ' horig'
USING eps_H;

-- Create H^2 matrix
drop table if exists H2 cascade;
create table H2 as
select 	H1.c1 as c1, 
		H2.c2 as c2,
		sum(H1.h*H2.h) as h 
from H H1, H H2
where H1.c2 = H2.c1 
group by H1.c1, H2.c2;

-- Drop all tables or views before the loop
FOR i IN 1..maxIterations LOOP
	V_1 := 'V1_'||i;
	V_2 := 'V2_'||i;
	B_new 	:= 'B_'||i;
	EXECUTE 'DROP VIEW IF EXISTS ' || V_1 || '  CASCADE';
	EXECUTE 'DROP VIEW IF EXISTS ' || V_2 || '  CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || B_new || '  CASCADE';	
END LOOP;

-- Start Timing
startTime := clock_timestamp();

-- Initialize B0 as B_old for the loop
drop table IF EXISTS B_0 CASCADE;		
EXECUTE 'create table B_0 as
select * 
from ' || E_input;


-- Actual loop
i = 1;
LOOP
	
	V_1 := 'V1_'||i;
	B_old := 'B_'||i-1;
	B_new := 'B_'||i;	

	-- Create view 1
	EXECUTE 'create view ' || V_1 || ' as
	select 	A.t as v, 
			H.c2 as c,
			sum(w*b*h) as b 
	from ' || A_input || ' A, ' || B_old || '  B, H
	where A.s = B.v
	and B.c = H.c1
	group by A.t, H.c2';


	-- If using 2nd order approximation (approxOption = 2)
	case 
	when approxOption = 2 then
	
		-- Create view 2
		V_2 := 'V2_'||i;
		EXECUTE 'create view ' || V_2 || ' as
		select 	B.v as v, 
				H2.c2 as c,	
				- sum(degree*b*h) as b 
		from D, ' || B_old || ' B , H2
		where B.c = H2.c1
		and B.v = D.v
		group by B.v, H2.c2';

		-- Combine E, V1, and V2
		EXECUTE 'create table ' || B_new || ' as 	
		select 	v, 
				c,
				sum(b) as b 
		from
			(select * from ' || E_input || ' E 
			union all 
			select * from ' || V_1 || ' V_1 
			union all
			select * from ' || V_2 || ' V_2) as X
		group by v, c';
	
	
	-- If using 1st order approximation (approxOption = 1)
	when approxOption = 1 then
		-- Combine E, and V1
		EXECUTE 'create table ' || B_new || ' as 	
		select 	v, 
				c,
				sum(b) as b 
		from
			(select * from ' || E_input || ' E 
			union all 
			select * from ' || V_1 || ' V_1) as X
		group by v, c';
		
	else
		RAISE WARNING 'input error: approxOptions not 1 or 2';		
	end case;
	

	-- stop if number of iterations so far >= maxIterations
	EXIT when  i >= maxIterations;


	-- only if a convergenceRatio is defined (>0), then verify whether convergence is already achieved
	if convergenceRatio > 0 then

		-- only if number of beliefs before this iteration and now are the same then continue 
		execute'select count(*) from ' || B_new 
		into n_B_new;
		execute'select count(*) from ' || B_old 
		into n_B_old;
		if 	n_B_new = n_B_old then 

			-- for each node, calculate the maximum belief before this iteration and now;
			-- for each node, calculate the absolute relative change before / now of maximum belief;
			-- calculate the maximum relative change across all nodes;
			-- EXIT if maximum relative change < convergenceRatio
			execute'(select max(diff)
				from (
					select case when (B1.b != 0) then @(B1.b-B2.b)/B1.b 
								when (B1.b = 0 and B1.b<>0) then 1
								else 0 end diff
					from (select v, max(b) b from ' || B_new || ' group by v) B1, 		
						 (select v, max(b) b from ' || B_old || ' group by v) B2 	
					where B1.v = B2.v) X)'
			into diff_max;
						
			-- RAISE WARNING 'iteration: %', i;
			-- RAISE WARNING 'diff_max: %', diff_max;
			EXIT when convergenceRatio > diff_max;
			
		end if;
	end if;

	i:=i+1;

END LOOP;

endTime := clock_timestamp();
timeLs :=  (1000*(extract(epoch from endTime)-extract(epoch from StartTime)))::int;

-- Store final beliefs
drop table if exists B_LinBP;
EXECUTE 'create table B_LinBP as
select * 
from '|| B_new;

-- Clean-up: Drop intermediate views after the loop
FOR i IN 1..maxiterations LOOP
	V_1 := 'V1_'||i;
	V_2 := 'V2_'||i;
	B_new 	:= 'B_'||i;
	EXECUTE 'DROP TABLE IF EXISTS ' || B_new || '  CASCADE';
	EXECUTE 'DROP VIEW IF EXISTS ' || V_1 || '  CASCADE';
	EXECUTE 'DROP VIEW IF EXISTS ' || V_2 || '  CASCADE';

END LOOP;

-- Calculate graph statistics
execute 
'select count(*) from
(select s from  ' || A_input || '
union
select t from  ' || A_input || ') as X'
into num_nodesTotal;

execute 'select count(distinct v) from ' || E_input
into num_nodesExplicit;

num_NodesImplicit := (select count(distinct v) from B_LinBP);

execute 'select count(*) from ' || A_input
into num_edges;

-- Save statistics
if debugMode = 1 then
	insert into Timing VALUES(	
		clock_timestamp(),
		timeLS,
		'LinBP',
		i,				-- how many iterations actually made
		A_input, 
		E_input, 
		H_input, 
		eps_H,
		comment,
		num_nodesExplicit,		
		num_nodesImplicit,			-- num_nodesAffected = Implicit if starting from scratch		
		num_nodesImplicit,
		num_nodesTotal,	
		num_edges);
end if;

-- Return results
return query select 
	timeLS,
	i,
	num_nodesExplicit,
	num_nodesImplicit,
	num_nodesImplicit,	
	num_nodesTotal,	
	num_edges;	 

END;
$BODY$
LANGUAGE plpgsql;

