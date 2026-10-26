// mlnix-parse: parse every file named in a list (one path per line) in ONE process and print
// each as `nix-instantiate --parse` would, or the parse error with its position.  Unlike
// `mlnix --parse` it does not stop at the first error, so two builds of the frontend can be
// compared byte for byte over a whole corpus (scripts/parse-corpus.py) in a few seconds.
#include "Nix/AST.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <sstream>

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "usage: mlnix-parse FILE-LIST\n";
    return 2;
  }
  std::ifstream list(argv[1]);
  std::string path;
  size_t files = 0, errors = 0, bytes = 0;
  auto t0 = std::chrono::steady_clock::now();
  while (std::getline(list, path)) {
    std::ifstream f(path, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    auto origin = std::make_shared<nixfe::Origin>();
    origin->name = origin->path = path;
    origin->baseDir = ".";
    origin->text = std::make_shared<std::string>(ss.str());
    bytes += origin->text->size();
    nixfe::ExprArena arena;
    nixfe::ParseOptions opts;
    opts.pipeOperators = true;
    opts.home = "/home";
    std::cout << "=== " << path << "\n";
    try {
      nixfe::showExpr(std::cout, nixfe::parse(arena, origin, opts));
      std::cout << "\n";
    } catch (const nixfe::ParseError &e) {
      errors++;
      std::cout << "ERROR " << e.what() << " @" << e.pos.line << ":" << e.pos.col << "\n";
    }
    files++;
  }
  double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  std::cerr << files << " files, " << bytes << " bytes, " << errors << " parse errors, " << s << " s (parse + print)\n";
}
