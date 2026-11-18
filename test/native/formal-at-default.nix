# a default that reads the @-name
(args@{ a, b ? args.a + 1 }: b) { a = 5; }
