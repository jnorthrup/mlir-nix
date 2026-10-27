// Reads cases from stdin, "<length> <seed> <chunk> <chunk> ... ;" per line, hashes the bytes of splitmix64(seed) in the given
// chunk sizes through nixstore::Sha256 (the last chunk repeats until the data is used up), prints the hex digest, and on the
// line "hw" prints whether the hardware path is in use.
#include "Nix/Sha256.h"

#include <cstdio>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

static uint64_t splitmix(uint64_t &x) {
  uint64_t z = (x += 0x9e3779b97f4a7c15ULL);
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
  return z ^ (z >> 31);
}

int main() {
  std::string line;
  while (std::getline(std::cin, line)) {
    if (line == "hw") {
      std::printf("%d\n", nixstore::Sha256::hardware() ? 1 : 0);
      continue;
    }
    std::istringstream in(line);
    size_t len;
    uint64_t seed;
    in >> len >> seed;
    std::vector<size_t> chunks;
    for (size_t c; in >> c;) chunks.push_back(c);
    if (chunks.empty()) chunks.push_back(len ? len : 1);
    std::vector<uint8_t> data(len);
    for (size_t i = 0; i < len; i++) data[i] = uint8_t(splitmix(seed));
    nixstore::Sha256 h;
    size_t off = 0, k = 0;
    while (off < len) {
      size_t c = chunks[k < chunks.size() ? k : chunks.size() - 1];
      k++;
      if (c > len - off) c = len - off;
      h.update(data.data() + off, c);
      off += c;
    }
    uint8_t out[32];
    h.final(out);
    for (int i = 0; i < 32; i++) std::printf("%02x", out[i]);
    std::printf("\n");
  }
}
