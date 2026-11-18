# a default that reads another formal
({ a, b ? a + 1 }: b) { a = 1; }
