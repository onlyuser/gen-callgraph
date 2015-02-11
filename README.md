gen-callgraph
=============

Copyright (C) 2011-2015 Jerry Chen <mailto:onlyuser@gmail.com>

About:
------

gen-callgraph is a script to generate call graph from binary.

Requirements
------------

* bash
* readelf
* objdump
* c++filt
* dot

Installation (Debian):
----------------------

1. git clone https://github.com/onlyuser/gen-callgraph.git

Usage
-----

<pre>
gen-call-graph &lt;BINARY&gt; | dot -Tpng -ocallgraph.png
</pre>

References
----------

<dl>
    <dt>"Disassemble raw x64 machine code"</dt>
    <dd>http://stackoverflow.com/questions/19071461/disassemble-raw-x64-machine-code</dd>

    <dt>"Graphviz - Graph Visualization Software"</dt>
    <dd>http://www.graphviz.org/</dd>
</dl>

Keywords
--------

    call graph, asm, disassembly, elf, graphviz, name mangling
