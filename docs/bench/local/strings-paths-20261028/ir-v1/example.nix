let
  make = marker: record: record.options._type == marker;
  first = make "option";
  second = make "changed";
  hop = pred: record: pred record;
  outer = pred: record: hop pred record;
  literal = record: record.options._type != "option";
  ready = { options._type = "option"; };
  selected = builtins.trace "path base" {
    options = builtins.trace "path intermediate" {
      _type = builtins.trace "selected string" "changed";
      unused = throw "unused path field";
    };
  };
in
  builtins.seq (outer first ready)
  (builtins.seq (outer first ready)
  (builtins.seq (outer first ready)
  (builtins.seq (outer first ready)
  (builtins.seq (literal ready)
  (builtins.seq (literal ready)
  (builtins.seq (literal ready)
  (builtins.seq (literal ready)
  (builtins.seq second [ (outer second selected) (outer first selected) (literal selected) ]))))))))
