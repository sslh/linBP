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
-- Provides function SBP_addBeliefs('A','En','comment', debugMode);
-- Changes the geodesic numbers G and implicit beliefs B based on additional beliefs En
-- First version: 11/29/2013,
-- This version: 6/28/2014 
-- Wolfgang Gatterbauer
--
-- Execute with: SELECT SBP_addBeliefs('A','En','comment', debugMode);
--
-- Requires the following tables to have been previously created and populated by SBP
--		H
--		G: will be changed
--		B: will be changed
-- 
-- Creates following intermediate tables (deletes them first if exists)
-- 		Gn
--		Bn
-- =================================================================================



-- DROP FUNCTION if exists SBP_addBeliefs(varchar, varchar, varchar, int);
CREATE OR REPLACE FUNCTION SBP_addBeliefs(	
	A_input varchar, 
	En_input varchar, 
	comment varchar,
	debugMode int)			-- 1: debug mode: save results in TimingTable, 0: does not	
	 
RETURNS TABLE(	
	timeLS int, 
	iterations int, 
	num_nodesExplicit int,	-- how many nodes have new explicit beliefs (table En)
	num_nodesAffected int,	-- how many nodes were affected in the process (implicit + explicit)	
	num_nodesImplicit int,	-- how many nodes have beliefs at the end (implicit + explicit)
	num_nodesTotal int,		-- number of nodes in graph
	numEdges int) as
	
$BODY$

DECLARE
	StartTime timestamptz;
	EndTime timestamptz;
	TimeLs int;
	numberInserted int;		-- stop condition: when no more Gn tuples were inserted during iteration
	i int;
	
	num_nodesExplicit int;	-- count number of nodes with explicit beliefs
	num_affectedNodes int;	-- count number of nodes affected by this run only 
	num_nodesImplicit int;	-- count number of nodes that have beliefs by the end of run
	num_nodesTotal int;		-- count number of nodes
	num_edges int; 			-- number of edges in A

BEGIN



-- Start timing
StartTime := clock_timestamp();

-- Initialize incremental result table Gn
drop table IF EXISTS Gn;
create table Gn(v int, g int, primary key (v));
EXECUTE 'insert into Gn
	select DISTINCT	En.v, 0 
	from ' || En_input || ' En';

-- Update G with new explicit nodes
update G
	set g=0
	where v in 
		(select Gn.v from Gn);
insert into G
	select Gn.v, 0
	from Gn 
	left outer join G on (G.v=Gn.v)
	where G.v is null;

-- Initialize incremental result tables Bn
drop table IF EXISTS Bn;
create table Bn(v int, c int, b double precision, primary key (v, c));
EXECUTE 'insert into Bn
	select * 
	from ' || En_input || ' En';

-- Initialize B with new explicit nodes
delete from B
	where v in (select Bn.v from Bn);
insert into B
	select * from Bn;



-- Actual loop
numberInserted := 1;			-- stop condition: when no more Gn tuples were inserted during iteration
i := 0;
WHILE numberInserted > 0 LOOP	-- Loop over geodesic numbers from i = 1
	i := i+1;
	
	-- Update Gn inside loop
	EXECUTE	'insert into Gn 
		(select X.v, $1
		from
			((select distinct A.t as v
			from Gn, ' || A_input || ' A
			where Gn.g = $1-1
			and Gn.v = A.s)
			except
			(select G.v
			from G
			where G.g < $1)) as X)'
	USING i;
	
	GET DIAGNOSTICS numberInserted = ROW_COUNT;		-- verify if something has changed
	if numberInserted > 0 then
	
		-- Update G inside loop for all entries in Gn with depth = i
		EXECUTE'update G
			set g= '|| i || '
			where v in 
				(select Gn.v from Gn where Gn.g = $1);
			insert into G
			select Gn.v, Gn.g 
				from Gn 
				left outer join G on (G.v=Gn.v)
				where G.v is null'
		USING i;
		
		-- Recreate Bn and calculate new entries inside loop
		drop table IF EXISTS Bn;
		create table Bn(v int, c int, b double precision, primary key (v, c));
		EXECUTE 'insert into Bn
			(select A.t, H.c2, sum(w*b*h) 
			from Gn, ' || A_input || ' A, B, H, G
			where Gn.g = $1
			and Gn.v = A.t
			and G.v = A.s	
			and G.g = $1-1	
			and A.s = B.v
			and B.c = H.c1
			group by A.t, H.c2)' 
		USING i;
		
		-- Update B inside loop
		delete from B
		where v in (select Bn.v from Bn);
		insert into B
		select * from Bn;
		
	END IF;
END LOOP;



EndTime := clock_timestamp();
TimeLs :=  (1000*(extract(epoch from EndTime)-extract(epoch from StartTime)))::int;

-- Calculate graph statistics
EXECUTE 
	'select count(*) from
	(select s from  ' || A_input || '
	union
	select t from  ' || A_input || ') as X'
	into num_nodesTotal;

EXECUTE 'select count(distinct v) from ' || En_input
	into num_nodesExplicit;

num_nodesImplicit := (select count(*) from G);

num_nodesAffected := (select count(*) from Gn);

execute 'select count(*) from ' || A_input
into num_edges;

-- Save statistics
if debugMode = 1 then
	insert into Timing VALUES(	
		clock_timestamp(),
		timeLS,
		'SBP_addBeliefs',
		i,					-- how many iterations including initialization
		A_input, 
		En_input, 
		null, 
		null,
		comment,
		num_nodesExplicit,		
		num_nodesAffected,			
		num_nodesImplicit,		
		num_nodesTotal,	
		num_edges);
end if;

-- Return results
return query select 
	timeLS,
	i-1,
	num_nodesExplicit,		--  new nodes
	num_nodesAffected,	
	num_nodesImplicit,	
	num_nodesTotal,	
	num_edges;
	
END;

$BODY$
LANGUAGE plpgsql;


