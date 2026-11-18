# a default never needed is never computed
({ a, b ? 9223372036854775807 + 1 }: a) { a = 1; }
