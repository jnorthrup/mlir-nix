# an @-pattern with `...`
(args@{ a, ... }: args.b) { a = 1; b = 2; }
