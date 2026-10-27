# Merging two attribute sets that collide twice reports the least name, not the first written.
{ a = { y = 1; x = 2; }; a = { y = 3; x = 4; }; }
