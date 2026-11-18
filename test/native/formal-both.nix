# a missing argument is named before an unexpected one (Nix's order)
({ a }: a) { b = 1; }
