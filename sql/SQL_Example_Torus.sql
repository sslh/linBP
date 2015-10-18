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
-- Paper experiment for Torus graph
-- First version: 6/24/2014
-- This version: 6/28/2014
-- Wolfgang Gatterbauer
-- =================================================================================



-- =================================================================================
-- (1) Create input data in database plus appropriate indices

-- A_torus: adjacency matrix
drop table if exists A_torus;
create table A_torus(s int, t int, w double precision, primary key (s, t));
create index sA_torus_idx ON A_torus(s);
create index tA_torus_idx ON A_torus(t);
insert into A_torus Values
	(1,5,1),
	(5,1,1),
	(2,6,1),
	(6,2,1),
	(3,7,1),
	(7,3,1),
	(4,8,1),
	(8,4,1),
	(5,6,1),
	(6,5,1),
	(6,7,1),
	(7,6,1),
	(7,8,1),
	(8,7,1),
	(8,5,1),
	(5,8,1);

-- E_torus: explicit beliefs
drop table if exists E_torus;
create table E_torus(v int, c int, b double precision, primary key (v, c));
insert into E_torus Values
	(1,1,2 ),
	(1,2,-1),
	(1,3,-1),
	(2,1,-1),
	(2,2,2 ),
	(2,3,-1),
	(3,1,-1),
	(3,2,-1),
	(3,3,2 );
	
-- H_torus: original (unscaled) H matrix; important not to use name 'H'
drop table if exists H_torus;
create table H_torus(c1 int, c2 int, h double precision, primary key (c1, c2));
insert into H_torus Values
	(1,1,0.266666667 ), 
	(1,2,-0.033333333),
	(1,3,0.366666667 ),
	(2,1,-0.033333333),
	(2,2,-0.333333333),
	(2,3,0.366666667 ),
	(3,1,-0.233333333),
	(3,2,0.366666667 ),
	(3,3,-0.133333333);




-- =================================================================================
-- (2) Example use of LinBP and SBP


-- Run LinBP
SELECT * from LinBP('A_torus','E_torus','H_torus',0.1, 100,'LinBP Torus', 1, 0.01,0);

-- Show all final beliefs
select * from B_LinBP order by v,c;

-- Show final beliefs only for our example node 4
drop table IF EXISTS B_LinBP_v;
create table B_LinBP_v as (select c,b from B_LinBP where v=4);
select * from B_LinBP_v;

-- return std of beliefs for node 4
select	stddev_pop(b) from B_LinBP_v;

-- return normalized final beliefs
select c, b*f as b
from B_LinBP_v, 	(select	1/stddev_pop(b) as f from B_LinBP_v) as X
order by c;


-- Run SBP
SELECT * from SBP('A_torus','E_torus','H_torus',0.1, 'SBP Torus',0);

-- Show all final beliefs
select * from B order by v,c;

-- shows final beliefs only for node 4
drop table IF EXISTS B_SBP_v4;
create table B_SBP_v4 as (select c,b from B where v=4);
select * from B_SBP_v4;

-- Return std of beliefs for node 4
select	stddev_pop(b) from B_SBP_v4;

-- return normalized final beliefs
select c, b*f as b
from B_SBP_v4, 	(select	1/stddev_pop(b) as f from B_SBP_v4) as X
order by c;





-- =================================================================================
-- (4) Result interpretation

-- Sufficient convergence guarantee for eps_H:
select * from fct_epsilonBound('A_torus', 'H_torus');

-- Comparing the top beliefs between LinBP and SBP
 select * from fct_beliefAccuracy('B_LinBP','B');







