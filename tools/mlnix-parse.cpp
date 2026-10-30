// mlnix-parse: parse every file named in a list (one path per line) in ONE process and print
// each as `nix-instantiate --parse` would, or the parse error with its position.  Unlike
// `mlnix --parse` it does not stop at the first error, so two builds of the frontend can be
// compared byte for byte over a whole corpus (scripts/parse-corpus.py) in a few seconds.
#include "Composite/CharSeries.h"
#include "Nix/Confix.h"
#include "Nix/Os.h"

#include <string.h>

using Entry = composite::Join<composite::Text, const nixfe::Source *>; // a file's path and its text

namespace {
/// The origin of a file of the list: named and placed by its path, relative paths from ".".
nixfe::Origin *originOf(const composite::Text &name, const nixfe::Source *text) {
  nixfe::Origin *o = nixfe::newOrigin();
  o->name = name.clone();
  o->path = name.clone();
  o->baseDir = ".";
  o->text = text;
  return o;
}

double seconds(uint64_t from, uint64_t to) { return double(to - from) / 1e9; }

/// Whether the two series of statement ends are the same numbers.
bool sameEnds(composite::Series<composite::Ptr<const uint32_t>> a, composite::Series<composite::Ptr<const uint32_t>> b) {
  return a.size() == b.size() && (a.size() == 0 || __builtin_memcmp(a.data(), b.data(), a.size() * sizeof(uint32_t)) == 0);
}

/// What the scan and the lexer each made of a file, as one line: `: scan accepts N bands, lexer accepts M`.
void verdict(composite::Text &t, bool okScan, size_t scanBands, bool okLex, size_t lexBands) {
  t.put(": scan ").put(okScan ? "accepts " : "rejects ").putUnsigned(scanBands).put(" bands, lexer ").put(okLex ? "accepts " : "rejects ").putUnsigned(lexBands).put('\n');
}
} // namespace

int main(int argc, char **argv) {
  // -n: time the parse alone, nothing printed (a skim: it builds nothing).  -m: map the files instead of reading them.
  bool quiet = false, map = false, bandsMode = false, scanOnly = false;
  unsigned fuzzSeed = 0;
  bool verbose = false;
  int a = 1;
  for (; a < argc && argv[a][0] == '-'; a++) {
    if (!strcmp(argv[a], "-n")) quiet = true;
    else if (!strcmp(argv[a], "-m")) map = true;
    else if (!strcmp(argv[a], "-b")) bandsMode = true;
    else if (!strcmp(argv[a], "-s")) scanOnly = true;
    else if (!strcmp(argv[a], "-v")) verbose = true;
    else if (!strcmp(argv[a], "-f") && a + 1 < argc - 1) {
      const char *seed = argv[++a];
      composite::text::Reading r = composite::facet<composite::text::Integer<10, false>>(composite::chars(seed, uint32_t(strlen(seed))));
      if (r.consumed == 0) a = argc;
      fuzzSeed = unsigned(r.value);
    } else a = argc;
  }
  if (a != argc - 1) {
    static const char usage[] = "usage: mlnix-parse [-n] [-m] [-b | -s] FILE-LIST\n"
                                "  -b: compare the Confix scan with the lexer's own delimiters over the list, and time both\n"
                                "  -s: time the Confix scan alone, ten passes over the list\n"
                                "  -v: with -b, say what each file did (for a short list)\n"
                                "  -f SEED: with -b, also compare the scan with the lexer on random mutations of the first 4000 files\n";
    nixsys::toStderr(usage, sizeof usage - 1);
    return 2;
  }
  composite::Text list;
  nixsys::readInto(argv[a], list); // a list that cannot be read is an empty one
  // Read everything first: the time reported is the parser's, not the file system's.
  composite::MutableSeries<Entry> corpus;
  size_t bytes = 0;
  composite::eachLine(list.data(), list.size(), [&](const char *p, uint32_t n) {
    composite::Text path(p, n);
    const nixfe::Source *src = map ? nixfe::Source::mapFile(path) : nullptr;
    if (!src) {
      composite::Text text;
      nixsys::readInto(path.c_str(), text);
      src = nixfe::Source::fromString(composite::mv(text));
    }
    bytes += src->view().size();
    corpus.append(Entry{composite::mv(path), src});
  });
  if (scanOnly) {
    size_t bandCount = 0;
    uint64_t t0 = nixsys::monotonicNs();
    nixfe::confix::Bands b; // reused: the time is the scan's, not the allocator's
    for (int rep = 0; rep < 10; rep++)
      for (auto &[name, text] : corpus) {
        b.clear();
        nixfe::confix::scan(text->view(), b);
        bandCount += b.size();
      }
    double s = seconds(t0, nixsys::monotonicNs());
    composite::Text t;
    t.put("scan: ");
    nixfe::printFloat(t, bytes * 10 / s / 1e6);
    t.put(" MB/s (").putUnsigned(bandCount / 10).put(" bands per pass)\n");
    nixsys::toStdout(t.data(), t.size());
    return 0;
  }
  if (bandsMode) {
    // The scan against the lexer's own delimiters: the same table, or both reject, for every file.
    double scanS = 0, lexS = 0;
    size_t agree = 0, bothReject = 0, disagree = 0, bandCount = 0;
    nixfe::ParseOptions opts;
    opts.pipeOperators = true;
    opts.home = "/home";
    for (auto &[name, text] : corpus) {
      nixfe::Origin *origin = originOf(name, text);
      nixfe::confix::Bands viaScan, viaLex;
      viaScan.rows.col<0>().reserve(text->view().size() / 48 + 16); // as the scan would, outside its time
      viaScan.rows.col<1>().reserve(text->view().size() / 48 + 16);
      uint64_t t0 = nixsys::monotonicNs();
      bool okScan = nixfe::confix::scan(text->view(), viaScan);
      uint64_t t1 = nixsys::monotonicNs();
      bool okLex = nixfe::confix::lexBands(origin, opts, viaLex);
      uint64_t t2 = nixsys::monotonicNs();
      scanS += seconds(t0, t1);
      lexS += seconds(t1, t2);
      bool same = okScan == okLex;
      if (same && okScan) {
        same = viaScan == viaLex; // bands and statements
        bandCount += viaScan.size();
      }
      composite::Text line;
      if (verbose) {
        line.put(same ? "ok       " : "DISAGREE ").put(name.data(), uint32_t(name.size()));
        verdict(line, okScan, viaScan.size(), okLex, viaLex.size());
      }
      if (!same) {
        if (++disagree <= 20) {
          line.put("DISAGREE ").put(name.data(), uint32_t(name.size()));
          verdict(line, okScan, viaScan.size(), okLex, viaLex.size());
          if (okScan && okLex)
            for (uint32_t i = 0; i < composite::min(viaScan.size(), viaLex.size()); i++)
              if (!(viaScan.span(i) == viaLex.span(i)) || viaScan.kind(i) != viaLex.kind(i) || !sameEnds(viaScan.stmts(i), viaLex.stmts(i))) {
                line.put("  first difference at band ").putUnsigned(i).put(": scan ").put(char(viaScan.kind(i))).put(" [");
                line.putUnsigned(viaScan.span(i).first()).put(',').putUnsigned(viaScan.span(i).second()).put("] lexer ").put(char(viaLex.kind(i))).put(" [");
                line.putUnsigned(viaLex.span(i).first()).put(',').putUnsigned(viaLex.span(i).second()).put("]\n");
                break;
              }
        }
      } else if (okScan) {
        agree++;
      } else {
        bothReject++;
      }
      nixsys::toStdout(line.data(), line.size());
    }
    if (fuzzSeed) {
      // Mutants: a delimiter, a quote, a comment opener or a path character inserted, a byte deleted or replaced.  Most are
      // not Nix; the scan and the lexer must still agree on whether they are balanced, and on the bands when they are.
      static const char *const pieces[] = {"{", "}", "[", "]", "(", ")", "\"", "''", "'", "${", "$", "$$", "#", "/*", "*/", "/", "//", "\\",
                                           "<", ">", "~/", ".", "-", "+", ":", ";", "http://", "a/", "/a", "./", "\n", "\r", "\t", " ", "0", "1.5", "or", "in", "?", "@"};
      uint64_t rng = 0x9E3779B97F4A7C15ull ^ fuzzSeed;
      auto next = [&] { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; };
      size_t mutants = 0, mAgree = 0, mBoth = 0, mDis = 0, mBands = 0;
      size_t limit = composite::min<size_t>(corpus.size(), 4000);
      for (size_t f = 0; f < limit; f++) {
        std::string_view orig = corpus[f].b->view();
        if (orig.empty() || orig.size() > 200000) continue;
        for (int k = 0; k < 4; k++) {
          composite::Text t(orig); // the one text that is mutated in the middle: inserted into, erased from
          int edits = 1 + int(next() % 3);
          for (int e = 0; e < edits && !t.empty(); e++) {
            size_t at = next() % t.size();
            switch (next() % 4) {
            case 0: case 1: t.insert(at, pieces[next() % (sizeof pieces / sizeof *pieces)]); break;
            case 2: t.erase(at, 1 + next() % 3); break;
            default: t[at] = char(next() % 256); break;
            }
          }
          auto src = nixfe::Source::fromString(t.clone());
          nixfe::Origin *origin = originOf(corpus[f].a, src);
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
            composite::Text line;
            line.put("MUTANT DISAGREES (file ").put(corpus[f].a.data(), uint32_t(corpus[f].a.size())).put(", mutant ").putInt(k).put(')');
            verdict(line, okScan, viaScan.size(), okLex, viaLex.size());
            nixsys::toStdout(line.data(), line.size());
            composite::Text file;
            file.put("/tmp/confix-mutant-").putUnsigned(mDis).put(".nix");
            if (FILE *out = fopen(file.cstr(), "wb")) {
              fwrite(t.data(), 1, t.size(), out);
              fclose(out);
            }
          }
        }
      }
      composite::Text line;
      line.putUnsigned(mutants).put(" mutants (seed ").putUnsigned(fuzzSeed).put("), ").putUnsigned(mBands).put(" bands: ").putUnsigned(mAgree).put(" agree, ");
      line.putUnsigned(mBoth).put(" rejected by both, ").putUnsigned(mDis).put(" DISAGREE\n");
      nixsys::toStdout(line.data(), line.size());
      disagree += mDis;
    }
    composite::Text line;
    line.putUnsigned(corpus.size()).put(" files, ").putUnsigned(bytes).put(" bytes, ").putUnsigned(bandCount).put(" bands: ").putUnsigned(agree).put(" agree, ");
    line.putUnsigned(bothReject).put(" rejected by both, ").putUnsigned(disagree).put(" DISAGREE\nscan ");
    nixfe::printFloat(line, scanS);
    line.put(" s (");
    nixfe::printFloat(line, bytes / scanS / 1e6);
    line.put(" MB/s)   lexer ");
    nixfe::printFloat(line, lexS);
    line.put(" s (");
    nixfe::printFloat(line, bytes / lexS / 1e6);
    line.put(" MB/s)   the scan is ");
    nixfe::printFloat(line, lexS / scanS);
    line.put("x faster\n");
    nixsys::toStdout(line.data(), line.size());
    return disagree ? 1 : 0;
  }
  size_t files = 0, errors = 0;
  uint64_t t0 = nixsys::monotonicNs();
  composite::Text shown; // a file's header and its tree, or its error: written whole
  for (auto &[name, text] : corpus) {
    nixfe::Origin *origin = originOf(name, text);
    nixfe::ParseOptions opts;
    opts.pipeOperators = true;
    opts.home = "/home";
    shown.clear();
    if (!quiet) shown.put("=== ").put(name.data(), uint32_t(name.size())).put('\n');
    try {
      if (quiet) {
        nixfe::skim(origin, opts);
      } else {
        nixfe::showSource(shown, origin, opts);
        shown.put('\n');
      }
    } catch (const nixfe::ParseError &e) {
      errors++;
      if (!quiet) shown.put("ERROR ").put(e.what()).put(" @").putUnsigned(e.pos.line).put(':').putUnsigned(e.pos.col).put('\n');
    }
    nixsys::toStdout(shown.data(), shown.size());
    files++;
  }
  double s = seconds(t0, nixsys::monotonicNs());
  composite::Text summary;
  summary.putUnsigned(files).put(" files, ").putUnsigned(bytes).put(" bytes, ").putUnsigned(errors).put(" parse errors, ");
  nixfe::printFloat(summary, s);
  summary.put(" s (").put(quiet ? "parse only" : "parse + print").put(")\n");
  nixsys::toStderr(summary.data(), summary.size());
}
