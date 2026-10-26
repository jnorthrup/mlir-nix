module {
  pdl.pattern @SelBaseOnly : benefit(0) {
    %0 = operand loc(#loc2)
    %1 = types loc(#loc3)
    %2 = operation "nix.select"(%0 : !pdl.value)  -> (%1 : !pdl.range<type>) loc(#loc3)
    rewrite %2 {
      replace %2 with(%0 : !pdl.value) loc(#loc5)
    } loc(#loc4)
  } loc(#loc1)
} loc(#loc)
#loc = loc("probe-select-ods.pdll":2:1)
#loc1 = loc("probe-select-ods.pdll":4:1)
#loc2 = loc("probe-select-ods.pdll":5:7)
#loc3 = loc("probe-select-ods.pdll":6:13)
#loc4 = loc("probe-select-ods.pdll":7:3)
#loc5 = loc("probe-select-ods.pdll":7:22)
