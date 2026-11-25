// The longest-match callback of the Nix delimiter scan (ConfixScan.mlir's nixfe_confix_match): the lexer's own rules,
// Nix/LexRules.h, shared with the lexer.  Compiled to LLVM IR by confix-bands.mlir's RUN line and linked with the scan.
#include "Nix/LexRules.h"

extern "C" unsigned long long nixfe_confix_match(const char *src, unsigned long long n, unsigned long long i) {
  nixfe::lex::Rules r(std::string_view(src, n));
  nixfe::lex::Match m = r.matchDefault(i, i < n ? src[i] : '\0');
  return ((unsigned long long)m.len << 32) | (unsigned long long)(unsigned)m.rule;
}
