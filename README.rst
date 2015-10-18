Linearized and Single-Pass Belief Propagation (LinBP and SBP) in SQL
====================================================================


Home of ``LinBP in SQL`` on github:
`http://github.com/sslh/linbp/ <http://github.com/sslh/linbp/>`__


Documentation
-------------

This is the SQL code (version July 17, 2014) for the experiments and methods described in the following paper:

1. `Linearized and Single-Pass Belief Propagation <http://www.vldb.org/pvldb/vol8.html>`__. `Wolfgang Gatterbauer <http://gatterbauer.co>`__, `Stephan Günnemann <http://www.cs.cmu.edu/~sguennem/>`__, `Danai Koutra <http://web.eecs.umich.edu/~dkoutra/>`__, `Christos Faloutsos <http://www.cs.cmu.edu/~christos/>`__. PVLDB 8(5): 581-592 (2015). [`Paper (PDF) <http://www.vldb.org/pvldb/vol8/p581-gatterbauer.pdf>`__], [`Full version (PDF) <http://arxiv.org/pdf/1406.7288>`__]



Usage & Documentation
---------------------

To run the code:

1. Run ONCE the code from:

.. code:: bash

	SQL_LinBP.sql
	SQL_SBP.sql
	SQL_SBP_addBeliefs.sql
	SQL_SBP_addEdges.sql

2. Run the SQL commands from:

.. code:: bash

	SQL_Example_Torus.sql


See annotations in individual files plus explanations in: <http://arxiv.org/abs/1406.7288>



--------------

License
-------
Copyright 2014 Wolfgang Gatterbauer, Stephan Guennemann, Danai Koutra, Christos Faloutsos

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.

Distributed in the hope that it will be useful to other researchers,
however, unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0

Questions
---------

Questions or comments about ``LinBP``? Drop me an email at
gatt@cmu.com.

