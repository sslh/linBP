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
-- Provides function SBP_addEdges('A','An','comment', debugMode);
-- Changes the geodesic numbers G and implicit beliefs B based on additional edges An
-- First version: 11/29/2013,
-- This version: 7/11/2014 
-- Wolfgang Gatterbauer
--
-- Execute with: SELECT SBP_addEdges('A','An','comment', debugMode);
--
-- Requires the following tables to have been previously created and populated by SBP
--		H
--		G: will be changed
--		B: will be changed
-- 
-- Creates following intermediate tables (deletes them first if exists)
-- 		Gn
-- 		Gnt
--		Bn
--		UpdatedNodes
-- =================================================================================

-- DROP FUNCTION if exists SBP_addEdges(varchar, varchar, varchar, int);
CREATE OR REPLACE FUNCTION SBP_addEdges(	
	A_input varchar, 
	An_input varchar, 
	comment varchar,
	debugMode int)				-- 1: debug mode: save results in TimingTable, 0: does not	
	 
RETURNS TABLE(	
	timeLS int, 
	iterations int, 
	num_edgesNew int,			-- how many new edges are added (table An): overloads "num_nodesExplicit"" 
	num_nodesAffected int,		-- how many nodes were affected in the process (implicit + explicit)	
	num_nodesImplicit int,		-- how many nodes have beliefs at the end (implicit + explicit)
	num_nodesTotal int,			-- number of nodes in graph
	numEdges int) as
	
$BODY$

DECLARE
	StartTime timestamptz;
	EndTime timestamptz;
	TimeLs int;
	numberInserted int;		-- stop condition: when no more Gn tuples were inserted during iteration
	i int;

	num_edgesNew int;		-- count number of new edges (overloads "num_nodesExplicit" in table Accuracy)
	num_affectedNodes int;	-- count number of nodes affected by this run only 
	num_nodesImplicit int;	-- count number of nodes that have beliefs by the end of run
	num_nodesTotal int;		-- count number of nodes
	num_edges int; 			-- number of edges in A

BEGIN

-- Start timing
StartTime := clock_timestamp();

-- Update A
EXECUTE ' insert into ' || A_input || ' 
	select * from ' || An_input;

-- Initialize incremental result table Gn
-- Left outer join is required for the case of disconnected components (nodes without a geodesic number)
drop table IF EXISTS Gn;
create table Gn(v int, g int, primary key (v));
EXECUTE 'insert into Gn 
	(select An.t, min(G1.g + 1) 
	from G G1 
	inner join ' || An_input || ' An 
	on G1.v = An.s	
	left outer join G G2 
	on G2.v = An.t		
	where (G2.g > G1.g or G2.g is null)
	group by An.t)';

-- Save the ids of nodes that get updated (allows duplicate ids); used only for statistics
drop table IF EXISTS UpdatedNodes;
create table UpdatedNodes(v int);
insert into UpdatedNodes
	select v from Gn;

-- Update G with new "seed nodes"
update G
	set g = 
		(select Gn.g from Gn
		where Gn.v = G.v)
	where v in 
		(select Gn.v from Gn);
insert into G
	select Gn.v, Gn.g
	from Gn 
	left outer join G on (G.v=Gn.v)
	where G.v is null;

-- Initialize incremental result tables Bn
drop table IF EXISTS Bn;
create table Bn(v int, c int, b double precision, primary key (v, c));
EXECUTE 'insert into Bn
	(select A.t, H.c2, sum(w*b*h) 
	from Gn, ' || A_input || ' A, B, H, G
	where Gn.v = A.t
	and G.v = A.s	
 	and G.g = Gn.g-1		
	and A.s = B.v
	and B.c = H.c1
	group by A.t, H.c2)';
	
-- Update B with new beliefs
delete from B
	where v in (select Bn.v from Bn);
insert into B
	select * from Bn;



-- Actual loop
numberInserted := 1;			-- stop condition: when no more Gn tuples were inserted during iteration
i := 0;							-- iterations just kept for statistics
WHILE numberInserted > 0 LOOP
	i := i+1;
	
	-- Update Gnt inside loop
	drop table IF EXISTS Gnt;
	create table Gnt(v int, g int, primary key (v));
	EXECUTE 'insert into Gnt 
		(select An.t, min(Gn.g + 1) 
		from Gn 
		inner join ' || A_input || ' An 
		on Gn.v = An.s	
		left outer join G 
		on G.v = An.t		
		where (G.g > Gn.g or G.g is null)
		group by An.t)';
		
	GET DIAGNOSTICS numberInserted = ROW_COUNT;
	if numberInserted > 0 then
		
		-- Add the ids of nodes that get updated; kept for statistics
		insert into UpdatedNodes
			select v from Gnt;
	
		-- Update G with new updated nodes
		update G
			set g = 
				(select Gnt.g from Gnt
				where Gnt.v = G.v)
			where v in 
				(select Gnt.v from Gnt);
		insert into G
			select Gnt.v, Gnt.g
			from Gnt 
			left outer join G on (G.v=Gnt.v)
			where G.v is null;		

		-- Recreate Bn and calculate new entries
		drop table IF EXISTS Bn;
		create table Bn(v int, c int, b double precision, primary key (v, c));
		EXECUTE 'insert into Bn
			(select A.t, H.c2, sum(w*b*h) 
			from Gnt, ' || A_input || ' A, B, H, G
			where Gnt.v = A.t
			and G.v = A.s	
			and G.g = Gnt.g-1			
			and A.s = B.v
			and B.c = H.c1
			group by A.t, H.c2)';

		-- Update B inside loop
		delete from B
			where v in (select Bn.v from Bn);
		insert into B
			select * from Bn;
			
		-- Replace Gn with Gnt	
		drop table Gn;	
		alter table Gnt rename to Gn;
			
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

EXECUTE 'select count(*) from ' || An_input		-- save number of new edges
	into num_edgesNew;

num_nodesImplicit := (select count(*) from G);

num_nodesAffected := (select count(DISTINCT v) from UpdatedNodes);

execute 'select count(*) from ' || A_input
into num_edges;

-- Save statistics
if debugMode = 1 then
	insert into Timing VALUES(	
		clock_timestamp(),
		timeLS,
		'SBP_addEdges',
		i,					-- how many iterations actually made
		A_input, 
		An_input, 
		null, 
		null,
		comment,
		null,
		-- num_edgesNew,		-- save number of new edges in column named "num_nodesExplicit"
		num_nodesAffected,			
		num_nodesImplicit,		
		num_nodesTotal,	
		num_edges);
end if;

-- Return results
return query select 
	timeLS,
	i-1,
	num_edgesNew,		--  new edges
	num_nodesAffected,	
	num_nodesImplicit,	
	num_nodesTotal,	
	num_edges;
	
END;

$BODY$
LANGUAGE plpgsql;

