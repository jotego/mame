Keep track of how many sub-sprite lists have been copied during DMA. This is the sum of all `length` values at cps3.cpp line 1663. Keep that sum as a class property. Then include it as part of the cache tile stats that we are displaying.

The sprite list copy at line 1664 of cps3.cpp assigns offs and length. When