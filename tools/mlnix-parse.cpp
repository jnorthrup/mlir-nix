// mlnix-parse: parse every file named in a list (one path per line) in ONE process and print
// each as `nix-instantiate --parse` would, or the parse error with its position.  Unlike
// `mlnix --parse` it does not stop at the first error, so two builds of the frontend can be
// compared byte for byte over a whole corpus (scripts/parse-corpus.py) in a few seconds.
#include "Nix/AST.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>

int main(int argc, char **argv) {
  bool quiet = argc == 3 && std::string(argv[1]) == "-n"; // time the parse alone: no AST printing
  if (argc != 2 && !quiet) {
    std::cerr << "usage: mlnix-parse [-n] FILE-LIST\n";
    return 2;
  }
  std::ifstream list(argv[quiet ? 2 : 1]);
  // Read everything first: the time reported is the parser's, not the file system's.
  std::vector<std::pair<std::string, std::string>> corpus;
  std::string path;
  size_t bytes = 0;
  while (std::getline(list, path)) {
    std::ifstream f(path, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    corpus.emplace_back(path, ss.str());
    bytes += corpus.back().second.size();
  }
  size_t files = 0, errors = 0;
  auto t0 = std::chrono::steady_clock::now();
  for (auto &[name, text] : corpus) {
    auto origin = std::make_shared<nixfe::Origin>();
    origin->name = origin->path = name;
    origin->baseDir = ".";
    origin->text = std::make_shared<std::string>(text);
    nixfe::ExprArena arena;
    nixfe::ParseOptions opts;
    opts.pipeOperators = true;
    opts.home = "/home";
    if (!quiet) std::cout << "=== " << name << "\n";
    try {
      nixfe::Expr *e = nixfe::parse(arena, origin, opts);
      if (!quiet) {
        nixfe::showExpr(std::cout, e);
        std::cout << "\n";
      }
    } catch (const nixfe::ParseError &e) {
      errors++;
      if (!quiet) std::cout << "ERROR " << e.what() << " @" << e.pos.line << ":" << e.pos.col << "\n";
    }
    files++;
  }
  double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  std::cerr << files << " files, " << bytes << " bytes, " << errors << " parse errors, " << s << " s (" << (quiet ? "parse only" : "parse + print") << ")\n";
}
