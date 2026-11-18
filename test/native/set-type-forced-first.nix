# refused: a printed set two of whose values may fail
# (mlnix forces `type` first, a symbol it interned before reading the program)
{ a = 9223372036854775807 + 1; type = 4611686018427387904 * 2; }
