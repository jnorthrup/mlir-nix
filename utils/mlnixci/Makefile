# mlnixci: build inside a Linux machine with mlnix built (MLIR_NIX/build, or MLNIX_BIN).  No C++: the server is MLIR
# (src/*.mlir and query.mlir) lowered to LLVM IR, with TrikeShed's Confix scanner (mlir-nix lib/Confix/confix.ll), and
# linked with libc and liburing-ffi only.  It lives in mlir-nix (utils/mlnixci/), so MLIR_NIX defaults to the
# enclosing checkout, wherever make is run from.
#   make MLNIX_BIN=<mlir-nix build>/bin      the server (MLNIX_BIN defaults to the checkout's build/bin)
#   make facet-check                          the compiled query against the same query counted by hand
#   make text-check                           text.mlir's escapes and digits against what the builder wrote before
#   make check NIXPKGS_LIB=...               both checks, then a server on os/ and test/e2e.py against it
#   sudo make install ...                    /opt/mlnixci and the systemd unit (Debian; NixOS: hyperv/nixos/mlnixci.nix)
MLIR_NIX ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
MLNIX_BIN ?= $(MLIR_NIX)/build/bin
MLNIX ?= $(MLNIX_BIN)/mlnix
MLNIX_OPT ?= $(MLNIX_BIN)/mlnix-opt
LLVM_BIN ?= /usr/lib/llvm-22/bin
PREFIX ?= /opt/mlnixci
NIXPKGS_LIB ?= $(PREFIX)/lib
BUILD ?= $(HOME)/mlnixci-build
PORT ?= 8080
CHECK_PORT ?= 8081

# series (coordinates, the builder) | confix (the handle of a JSON text's index) | corpus (the columns) | eval (mlnix as a
# child) | api (the routes) | http (the ring, connections, main)
MODULES = series confix corpus eval api http
LOWER = --convert-scf-to-cf --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm \
  --reconcile-unrealized-casts
# after mlnix-opt: buffers freed where they die, a slice's offset (an affine.apply once the metadata is expanded) lowered
LOWER_BUFFERS = --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification \
  --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm \
  $(LOWER)

all: $(BUILD)/mlnixci

# Written in TrikeShed's ops (and confix's index): query.mlir (the facets), src/index.mlir (a JSON text's index),
# src/columns.mlir (the columns' codes, the rows' order), src/text.mlir (a string's escapes, a number's digits),
# src/load.mlir (a corpus's columns, made at load) and src/reads.mlir (a text's bytes searched and read)
# -> scf/arith/memref (mlnix-opt) -> LLVM dialect -> LLVM IR.
TRIKESHED = index columns text load reads
$(BUILD)/query.ll: query.mlir
	mkdir -p $(BUILD)
	$(MLNIX_OPT) $< --trikeshed-lower-cursors > $(BUILD)/query.lowered.mlir
	! grep -q 'trikeshed\.' $(BUILD)/query.lowered.mlir
	$(LLVM_BIN)/mlir-opt $(BUILD)/query.lowered.mlir $(LOWER_BUFFERS) | $(LLVM_BIN)/mlir-translate --mlir-to-llvmir -o $@

$(TRIKESHED:%=$(BUILD)/%.ll): $(BUILD)/%.ll: src/%.mlir
	mkdir -p $(BUILD)
	$(MLNIX_OPT) $< --trikeshed-lower-cursors > $(BUILD)/$*.lowered.mlir
	! grep -q -E '(trikeshed|confix)\.' $(BUILD)/$*.lowered.mlir
	$(LLVM_BIN)/mlir-opt $(BUILD)/$*.lowered.mlir $(LOWER_BUFFERS) | $(LLVM_BIN)/mlir-translate --mlir-to-llvmir -o $@

$(BUILD)/%.ll: src/%.mlir
	mkdir -p $(BUILD)
	$(LLVM_BIN)/mlir-opt $< $(LOWER) | $(LLVM_BIN)/mlir-translate --mlir-to-llvmir -o $@

$(BUILD)/confix-scan.ll: $(MLIR_NIX)/lib/Confix/confix.ll
	mkdir -p $(BUILD)
	cp $< $@

$(BUILD)/%.o: $(BUILD)/%.ll
	$(LLVM_BIN)/clang -c -O2 -Wno-override-module $< -o $@
	$(LLVM_BIN)/llvm-objcopy --localize-symbol=dealloc_helper $@
# (--bufferization-lower-deallocations writes a public @dealloc_helper into each module that frees several buffers at
# once; each module keeps its own)

# the compiled query alone, for test/facet_check.py
$(BUILD)/query.so: $(BUILD)/query.ll
	$(LLVM_BIN)/clang -shared -fPIC -O2 -Wno-override-module $< -o $@

facet-check: $(BUILD)/query.so
	python3 test/facet_check.py $(BUILD)/query.so

# text.mlir alone, for test/text_check.py
$(BUILD)/text.so: $(BUILD)/text.ll
	$(LLVM_BIN)/clang -shared -fPIC -O2 -Wno-override-module $< -o $@

text-check: $(BUILD)/text.so
	python3 test/text_check.py $(BUILD)/text.so

# linked by the C driver: libc and liburing-ffi (liburing's inline helpers as functions); no C++ library
$(BUILD)/mlnixci: $(MODULES:%=$(BUILD)/%.o) $(BUILD)/query.o $(TRIKESHED:%=$(BUILD)/%.o) $(BUILD)/confix-scan.o
	$(LLVM_BIN)/clang -O2 $^ -luring-ffi -o $@
	! ldd $@ | grep -E 'libstdc\+\+|libc\+\+|libgcc_s'

check: $(BUILD)/mlnixci facet-check text-check
	$(BUILD)/mlnixci --corpus os/eval.nix --arg lib "import $(NIXPKGS_LIB)" --page www/index.html --mlnix $(MLNIX) \
	  --state $(BUILD) --port $(CHECK_PORT) & \
	  pid=$$!; \
	  for i in $$(seq 100); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $(CHECK_PORT)), 0.2)" 2>/dev/null && break; sleep 0.1; done; \
	  python3 test/e2e.py http://127.0.0.1:$(CHECK_PORT); \
	  rc=$$?; kill $$pid; wait $$pid 2>/dev/null; exit $$rc

install: $(BUILD)/mlnixci
	install -Dm755 $(BUILD)/mlnixci $(PREFIX)/bin/mlnixci
	install -Dm755 $(MLNIX) $(PREFIX)/bin/mlnix
	install -Dm644 www/index.html $(PREFIX)/www/index.html
	install -Dm644 www/luci.html $(PREFIX)/www/luci.html
	for f in corpus.nix facets.nix answer.nix runtime.nix; do install -Dm644 $$f $(PREFIX)/$$f; done
	for f in options.nix eval.nix etc.nix settings.json; do install -Dm644 os/$$f $(PREFIX)/os/$$f; done
	rm -rf $(PREFIX)/lib && cp -a $(NIXPKGS_LIB) $(PREFIX)/lib
	sed 's/@PORT@/$(PORT)/' mlnixci.service > /etc/systemd/system/mlnixci.service
	systemctl daemon-reload

.PHONY: all check facet-check install
