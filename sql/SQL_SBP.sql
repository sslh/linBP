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
-- Provides function SBP('A','E','H',esp_H,'comment', debugMode);
-- Calculates the final beliefs for SBP
-- Wolfgang Gatterbauer: 11/29/2013, 2/28/2014, 5/31/2014, 6/24/2014
-- Stephan Guennemann: 12/04/2013
--
-- Execute with: SELECT SBP('A','E','H',eps_H,'comment',0);
--		
-- Creates following tables (delete if exists)
--  	H(c1,c2,h): coupling matrix from H_input and eps_H
-- 		G(v,g): geodesic number g for each node v
--		B(v,c,b): contains final beliefs
-- =================================================================================

-- DROP FUNCTION SBP(varchar, varchar, varchar, double precision, varchar, int);
CREATE OR REPLACE FUNCTION SBP(	
	A_input varchar, 
	E_input varchar, 
	H_input varchar, 									
	eps_H double precision, 
	comment varchar,
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
	StartTime timestamptz;
	EndTime timestamptz;
	TimeLs int;
	numberInserted int;
	i int;

	num_nodesExplicit int;	-- count number of nodes with explicit beliefs
	num_nodesImplicit int;	-- count number of nodes affected by this run
	num_nodesTotal int;		-- count number of nodes
	num_edges int; 			-- number of edges in A

BEGIN


-- Create table H
drop table IF EXISTS H cascade;
EXECUTE 'create table H as
select 	horig.c1 as c1, 
		horig.c2 as c2, 
		horig.h*$1 as h 
from ' || H_input || ' horig'
USING eps_H;

-- Create result tables G, B: can be done offline
drop table IF EXISTS G cascade;
create table G(v int, g int, primary key (v));	
drop table IF EXISTS B cascade;
create table B(v int, c int, b double precision, primary key (v, c));

-- Start timing
StartTime := clock_timestamp();

-- Initialize tables G, B
EXECUTE 'insert into G
select distinct E.v, 0 
from ' || E_input || ' E';
EXECUTE 'insert into B
select * 
from ' || E_input || ' E';


-- Actual loop
numberInserted := 1;			-- stop condition: when no more Gn tuples were inserted during iteration
i := 0;							
WHILE numberInserted > 0 LOOP	-- Loop over geodesic numbers from i = 1
	i := i+1;

	-- Update G inside loop for all entries in Gn with depth = i	
	EXECUTE 'insert into G 			
	(select DISTINCT A.t, $1 				
	from G 
	inner join ' || A_input || ' A on (G.v = A.s)
	left outer join G G2 on (A.t = G2.v)
	where G.g = $1-1	
	and G2.v is null)' 
	USING i;
	
	GET DIAGNOSTICS numberInserted = ROW_COUNT;
	if numberInserted > 0 then
		
		-- Update B inside loop
		EXECUTE 'insert into B
		(select 	A.t, 
					H.c2, 
					sum(w*b*h) 
		from G, ' || A_input || ' A, B, H, G G2
		where G.g = $1
		and G.v = A.t
		and A.s = B.v
		and B.c = H.c1
		and G2.v = A.s
		and G2.g = $1 - 1
		group by A.t, H.c2)'
		USING i;
	
	END IF;
END LOOP;


EndTime := clock_timestamp();
TimeLs :=  (1000*(extract(epoch from EndTime)-extract(epoch from StartTime)))::int;

-- Calculate graph statistics
execute 
'select count(*) from
(select s from  ' || A_input || '
union
select t from  ' || A_input || ') as X'
into num_nodesTotal;

execute 'select count(distinct v) from ' || E_input
into num_nodesExplicit;

num_NodesImplicit := (select count(*) from G);

execute 'select count(*) from ' || A_input
into num_edges;

-- Save statistics
if debugMode = 1 then
	insert into Timing VALUES(	
		clock_timestamp(),
		timeLS,
		'SBP',
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
