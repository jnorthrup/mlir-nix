# an `or` default never needed is never computed
{ a = 1; }.a or (9223372036854775807 + 1)
