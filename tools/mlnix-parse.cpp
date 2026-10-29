// mlnix-parse: parse every file named in a list (one path per line) in ONE process and print
// each as `nix-instantiate --parse` would, or the parse error with its position.  Unlike
// `mlnix --parse` it does not stop at the first error, so two builds of the frontend can be
// compared byte for byte over a whole corpus (scripts/parse-corpus.py) in a few seconds.
#include "Nix/Confix.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>

int main(int argc, char **argv) {
  // -n: time the parse alone, nothing printed (a skim: it builds nothing).  -m: map the files instead of reading them.
  bool quiet = false, map = false, bandsMode = false, scanOnly = false;
  unsigned fuzzSeed = 0;
  bool verbose = false;
  int a = 1;
  for (; a < argc && argv[a][0] == '-'; a++) {
    if (std::string(argv[a]) == "-n") quiet = true;
    else if (std::string(argv[a]) == "-m") map = true;
    else if (std::string(argv[a]) == "-b") bandsMode = true;
    else if (std::string(argv[a]) == "-s") scanOnly = true;
    else if (std::string(argv[a]) == "-v") verbose = true;
    else if (std::string(argv[a]) == "-f" && a + 1 < argc - 1) fuzzSeed = unsigned(std::stoul(argv[++a]));
    else a = argc;
  }
  if (a != argc - 1) {
    std::cerr << "usage: mlnix-parse [-n] [-m] [-b | -s] FILE-LIST\n"
                 "  -b: compare the Confix scan with the lexer's own delimiters over the list, and time both\n"
                 "  -s: time the Confix scan alone, ten passes over the list\n"
                 "  -v: with -b, say what each file did (for a short list)\n"
                 "  -f SEED: with -b, also compare the scan with the lexer on random mutations of the first 4000 files\n";
    return 2;
  }
  std::ifstream list(argv[a]);
  // Read everything first: the time reported is the parser's, not the file system's.
  std::vector<std::pair<std::string, std::shared_ptr<const nixfe::Source>>> corpus;
  std::string path;
  size_t bytes = 0;
  while (std::getline(list, path)) {
    std::shared_ptr<const nixfe::Source> src = map ? nixfe::Source::mapFile(path) : nullptr;
    if (!src) {
      std::ifstream f(path, std::ios::binary);
      std::stringstream ss;
      ss << f.rdbuf();
      src = nixfe::Source::fromString(ss.str());
    }
    bytes += src->view().size();
    corpus.emplace_back(path, std::move(src));
  }
  if (scanOnly) {
    using clock = std::chrono::steady_clock;
    size_t bandCount = 0;
    auto t0 = clock::now();
    nixfe::confix::Bands b; // reused: the time is the scan's, not the allocator's
    for (int rep = 0; rep < 10; rep++)
      for (auto &[name, text] : corpus) {
        b.clear();
        nixfe::confix::scan(text->view(), b);
        bandCount += b.size();
      }
    double s = std::chrono::duration<double>(clock::now() - t0).count();
    std::cout << "scan: " << bytes * 10 / s / 1e6 << " MB/s (" << bandCount / 10 << " bands per pass)\n";
    return 0;
  }
  if (bandsMode) {
    // The scan against the lexer's own delimiters: the same table, or both reject, for every file.
    using clock = std::chrono::steady_clock;
    double scanS = 0, lexS = 0;
    size_t agree = 0, bothReject = 0, disagree = 0, bandCount = 0;
    nixfe::ParseOptions opts;
    opts.pipeOperators = true;
    opts.home = "/home";
    for (auto &[name, text] : corpus) {
      auto origin = std::make_shared<nixfe::Origin>();
      origin->name = origin->path = name;
      origin->baseDir = ".";
      origin->text = text;
      nixfe::confix::Bands viaScan, viaLex;
      viaScan.rows.col<0>().reserve(text->view().size() / 48 + 16); // as the scan would, outside its time
      viaScan.rows.col<1>().reserve(text->view().size() / 48 + 16);
      auto t0 = clock::now();
      bool okScan = nixfe::confix::scan(text->view(), viaScan);
      auto t1 = clock::now();
      bool okLex = nixfe::confix::lexBands(origin, opts, viaLex);
      auto t2 = clock::now();
      scanS += std::chrono::duration<double>(t1 - t0).count();
      lexS += std::chrono::duration<double>(t2 - t1).count();
      bool same = okScan == okLex;
      if (same && okScan) {
        same = viaScan == viaLex; // bands and statements
        bandCount += viaScan.size();
      }
      if (verbose)
        std::cout << (same ? "ok       " : "DISAGREE ") << name << ": scan " << (okScan ? "accepts " : "rejects ") << viaScan.size()
                  << " bands, lexer " << (okLex ? "accepts " : "rejects ") << viaLex.size() << "\n";
      if (!same) {
        if (++disagree <= 20) {
          std::cout << "DISAGREE " << name << ": scan " << (okScan ? "accepts " : "rejects ") << viaScan.size()
                    << " bands, lexer " << (okLex ? "accepts " : "rejects ") << viaLex.size() << "\n";
          if (okScan && okLex)
            for (uint32_t i = 0; i < std::min(viaScan.size(), viaLex.size()); i++)
              if (!(viaScan.span(i) == viaLex.span(i)) || viaScan.kind(i) != viaLex.kind(i) ||
                  !std::equal(viaScan.stmts(i).begin(), viaScan.stmts(i).end(), viaLex.stmts(i).begin(), viaLex.stmts(i).end())) {
                std::cout << "  first difference at band " << i << ": scan " << char(viaScan.kind(i)) << " ["
                          << viaScan.span(i).first() << "," << viaScan.span(i).second() << "] lexer "
                          << char(viaLex.kind(i)) << " [" << viaLex.span(i).first() << "," << viaLex.span(i).second() << "]\n";
                break;
              }
        }
      } else if (okScan) {
        agree++;
      } else {
        bothReject++;
      }
    }
    if (fuzzSeed) {
      // Mutants: a delimiter, a quote, a comment opener or a path character inserted, a byte deleted or replaced.  Most are
      // not Nix; the scan and the lexer must still agree on whether they are balanced, and on the bands when they are.
      static const char *const pieces[] = {"{", "}", "[", "]", "(", ")", "\"", "''", "'", "${", "$", "$$", "#", "/*", "*/", "/", "//", "\\",
                                           "<", ">", "~/", ".", "-", "+", ":", ";", "http://", "a/", "/a", "./", "\n", "\r", "\t", " ", "0", "1.5", "or", "in", "?", "@"};
      uint64_t rng = 0x9E3779B97F4A7C15ull ^ fuzzSeed;
      auto next = [&] { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; };
      size_t mutants = 0, mAgree = 0, mBoth = 0, mDis = 0, mBands = 0;
      size_t limit = std::min<size_t>(corpus.size(), 4000);
      for (size_t f = 0; f < limit; f++) {
        std::string_view orig = corpus[f].second->view();
        if (orig.empty() || orig.size() > 200000) continue;
        for (int k = 0; k < 4; k++) {
          std::string t(orig);
          int edits = 1 + int(next() % 3);
          for (int e = 0; e < edits && !t.empty(); e++) {
            size_t at = next() % t.size();
            switch (next() % 4) {
            case 0: case 1: t.insert(at, pieces[next() % (sizeof pieces / sizeof *pieces)]); break;
            case 2: t.erase(at, 1 + next() % 3); break;
            default: t[at] = char(next() % 256); break;
            }
          }
          auto src = nixfe::Source::fromString(t);
          auto origin = std::make_shared<nixfe::Origin>();
          origin->name = origin->path = corpus[f].first;
          origin->baseDir = ".";
          origin->text = src;
          nixfe::confix::Bands viaScan, viaLex;
          bool okScan = nixfe::confix::scan(src->view(), viaScan);
          bool okLex = nixfe::confix::lexBands(origin, opts, viaLex);
          mutants++;
          bool same = okScan == okLex;
          if (same && okScan) {
            same = viaScan == viaLex;
            mBands += viaScan.size();
          }
          if (same) {
            (okScan ? mAgree : mBoth)++;
          } else if (++mDis <= 5) {
            std::cout << "MUTANT DISAGREES (file " << corpus[f].first << ", mutant " << k << "): scan " << (okScan ? "accepts " : "rejects ")
                      << viaScan.size() << " bands, lexer " << (okLex ? "accepts " : "rejects ") << viaLex.size() << "\n";
            std::ofstream("/tmp/confix-mutant-" + std::to_string(mDis) + ".nix", std::ios::binary) << t;
          }
        }
      }
      std::cout << mutants << " mutants (seed " << fuzzSeed << "), " << mBands << " bands: " << mAgree << " agree, " << mBoth
                << " rejected by both, " << mDis << " DISAGREE\n";
      disagree += mDis;
    }
    std::cout << corpus.size() << " files, " << bytes << " bytes, " << bandCount << " bands: " << agree << " agree, "
              << bothReject << " rejected by both, " << disagree << " DISAGREE\n"
              << "scan " << scanS << " s (" << bytes / scanS / 1e6 << " MB/s)   lexer " << lexS << " s (" << bytes / lexS / 1e6
              << " MB/s)   the scan is " << lexS / scanS << "x faster\n";
    return disagree ? 1 : 0;
  }
  size_t files = 0, errors = 0;
  auto t0 = std::chrono::steady_clock::now();
  for (auto &[name, text] : corpus) {
    auto origin = std::make_shared<nixfe::Origin>();
    origin->name = origin->path = name;
    origin->baseDir = ".";
    origin->text = text;
    nixfe::ParseOptions opts;
    opts.pipeOperators = true;
    opts.home = "/home";
    if (!quiet) std::cout << "=== " << name << "\n";
    try {
      if (quiet) {
        nixfe::skim(origin, opts);
      } else {
        nixfe::showSource(std::cout, origin, opts);
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
