# an argument the body never forces is never computed
let f = x: 5; in f (9223372036854775807 + 1)
