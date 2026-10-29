// The chunked body: a cell never moves while more are appended, the series reads as one through its index function, and drain and clear work as
// on every body.  Build like minmax-check.cc.
#include "Composite/Folds.h"
#include "Composite/Mutable.h"
#include <cstdio>
#include <cstdlib>
#include <string>
using namespace composite;
static void require(bool ok, const char *what) { if (!ok) { std::printf("FAIL %s\n", what); std::exit(1); } }
int main() {
  MutableSeries<int, Chunked<int, 4>> m;
  int *first = nullptr;
  for (int i = 0; i < 100000; i++) {
    m.append(i);
    if (i == 0) first = &m[0];
  }
  require(m.size() == 100000, "size");
  require(first == &m[0], "a cell never moves across appends");
  uint64_t sum = 0;
  for (int x : m) sum += uint64_t(x);
  require(sum == 99999ull * 100000 / 2, "range-for over the chunks");
  require(m.back() == 99999 && m.front() == 0 && m[16] == 16 && m[15] == 15, "chunk edges");
  // strings: non-trivial cells, drained and cleared
  MutableSeries<std::string, Chunked<std::string, 3>> s;
  for (int i = 0; i < 1000; i++) s.append("item " + std::to_string(i));
  const std::string *p500 = &s[500];
  for (int i = 0; i < 1000; i++) s.append("more");
  require(p500 == &s[500] && s[500] == "item 500", "string cells stay put");
  require(s.drain(3) == "item 3" && s[3].empty(), "drain leaves a default cell");
  s.pop(); require(s.size() == 1999, "pop");
  s.clear(); require(s.empty(), "clear");
  // move: the cells and their addresses go to the new owner
  MutableSeries<int, Chunked<int, 4>> a; for (int i = 0; i < 50; i++) a.append(i);
  int *at = &a[10];
  MutableSeries<int, Chunked<int, 4>> b = static_cast<MutableSeries<int, Chunked<int, 4>> &&>(a);
  require(&b[10] == at && a.empty() && b.size() == 50, "a move hands over the chunks");
  std::printf("PASS chunked: %zu cells in chunks of 16, none moved; strings, drain, pop, clear, move\n", size_t(m.size()));
  return 0;
}
