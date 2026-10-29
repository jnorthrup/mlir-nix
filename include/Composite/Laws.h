//===- Laws.h - the self-tests of the algebra, checked by including this header ---===//

#ifndef COMPOSITE_LAWS_H
#define COMPOSITE_LAWS_H

#include "Composite/Folds.h"
#include "Composite/Pool.h"
#include "Composite/Series.h"

namespace composite {

//===----------------------------------------------------------------------===//
// The laws, checked wherever this header is included
//===----------------------------------------------------------------------===//

constexpr bool lawsHold() {
  auto at = [](uint32_t i) { return int(i) * 10; };
  Series<decltype(at)> xs = 3u |j| at;
  auto inc = [](int x) { return x + 1; };
  auto dbl = [](int x) { return x * 2; };
  bool project = (xs |α| inc)[2] == 21;
  bool fuse = ((xs |α| inc) |α| dbl)[1] == 22; // α of α reads as α of the composition
  auto pair = 1 |j| 2;                          // two small scalars: the packed word
  int sum = 0;
  for (int x : xs) sum += x;
  return project && fuse && pair.first() == 1 && pair.second() == 2 && sum == 30 && (xs |α| inc).size() == 3;
}
constexpr bool selectHolds() {
  int a[] = {10, 30, 50}, b[] = {20};
  join::TwInt sel[] = {join::TwInt(0, 0), join::TwInt(0, 1), join::TwInt(1, 0)}; // a[0], b[0], a[1]
  auto m = select(series(a, 3), series(b, 1), series(sel, 3));
  int sum = 0;
  for (int x : m) sum += x;
  return m.size() == 3 && m[0] == 10 && m[1] == 20 && m[2] == 30 && sum == 60;
}
static_assert(lawsHold(), "the Series laws do not hold");
static_assert(selectHolds(), "the select law does not hold: a row is read where it lies, by row j side");

} // namespace composite

#endif
