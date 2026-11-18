# a value never selected is never computed
{ a = 1; b = 9223372036854775807 + 1; }.a
