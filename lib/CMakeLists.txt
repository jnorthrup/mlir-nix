add_mlir_dialect_library(MLIRNix
  Dialect/NixDialect.cpp
  Dialect/NixPrimDialects.cpp
  Dialect/MlnixControlDialect.cpp
  Dialect/KifDialect.cpp
  Dialect/KifImport.cpp
  Dialect/KifChase.cpp
  Dialect/KifLean.cpp
  Dialect/KifTptp.cpp
  Dialect/KifTrikeShed.cpp
  Dialect/SumoDialect.cpp
  Dialect/SonDialect.cpp
  Dialect/ConfixDialect.cpp
  Dialect/KursiveDialect.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS MLIRNixOpsIncGen TrikeShedIncGen
  LINK_LIBS PUBLIC MLIRTrikeShed MLIRIR MLIRPass MLIRTransforms MLIRTransformUtils MLIRRewrite MLIRSideEffectInterfaces MLIRIRDL MLIRParser MLIRLLVMDialect)

# The Confix scanner is LLVM IR (Confix/confix.ll, freestanding: it calls nothing).  opt and llc make its object, which MLIRNix carries, so that
# whatever links the library can call confix_scan_json and confix_scan_cbor, which the confix-to-llvm pass lowers to.
find_program(MLNIX_OPT opt HINTS ${LLVM_TOOLS_BINARY_DIR})
find_program(MLNIX_LLC llc HINTS ${LLVM_TOOLS_BINARY_DIR})
if(NOT MLNIX_OPT OR NOT MLNIX_LLC)
  message(FATAL_ERROR "opt and llc are needed to build lib/Confix/confix.ll")
endif()
set(CONFIX_LL ${CMAKE_CURRENT_SOURCE_DIR}/Confix/confix.ll)
set(CONFIX_OBJ ${CMAKE_CURRENT_BINARY_DIR}/confix.o)
add_custom_command(OUTPUT ${CONFIX_OBJ}
  COMMAND ${MLNIX_OPT} -O3 ${CONFIX_LL} -o ${CMAKE_CURRENT_BINARY_DIR}/confix.bc
  COMMAND ${MLNIX_LLC} -O3 -filetype=obj -relocation-model=pic ${CMAKE_CURRENT_BINARY_DIR}/confix.bc -o ${CONFIX_OBJ}
  DEPENDS ${CONFIX_LL}
  COMMENT "Confix scanner (LLVM IR)")
set_source_files_properties(${CONFIX_OBJ} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
target_sources(MLIRNix PRIVATE ${CONFIX_OBJ})

# TrikeShed's kernel as a dialect: Join, MetaSeries, Series, Series2, split, Cursor, α, ↺ and the combinators of
# borg.trikeshed.lib, generated from include/Composite/TrikeShed.td.
add_mlir_dialect_library(MLIRTrikeShed
  Composite/TrikeShedDialect.cpp
  Composite/ClusterLowering.cpp
  Composite/CursorLowering.cpp
  Composite/TwinRouting.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS TrikeShedIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRSideEffectInterfaces MLIRFuncDialect MLIRMemRefDialect MLIRPass
                   MLIRArithDialect MLIRSCFDialect MLIRSCFTransforms MLIRFuncTransforms MLIRTransformUtils MLIRLLVMDialect)

add_library(TrikeShedRuntime SHARED Composite/ClusterRuntime.cpp)
set_target_properties(TrikeShedRuntime PROPERTIES LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)

add_library(NixStore STATIC Store/Hash.cpp Store/StorePaths.cpp Store/LocalStore.cpp Store/StructuredAttrs.cpp Store/Prefetch.cpp Store/Ed25519.cpp)
target_link_libraries(NixStore PUBLIC LLVMSupport)
# SHA-256 is lowered/nixstore/Sha256.mlir (below, with the other lowered modules): its rounds are the CPU's SHA-2 instructions
# where the processor has them, else portable.  On arm64 that is the rate of CommonCrypto and of libcrypto (measured
# within 5% of each from 1 KiB to 16 MiB, faster on shorter inputs), so neither is linked.  On x86_64 a CPU without SHA-NI
# runs the portable rounds, at about half the rate of libcrypto's AVX2 code (230 against 485 MB/s on a Skylake), so there
# libcrypto is linked when there is one (libcrypto.a preferred: loading libcrypto.so is 0.6 ms of the 10 ms an `eval -E 1`
# takes, the static one 0.15 ms).
set(MLNIX_SHA256 "auto" CACHE STRING "SHA-256 code: auto (the MLIR module; on x86_64 OpenSSL if found), mlir or openssl")
if(MLNIX_SHA256 STREQUAL "openssl" OR (MLNIX_SHA256 STREQUAL "auto" AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$"))
  set(OPENSSL_USE_STATIC_LIBS ON)
  find_package(OpenSSL QUIET)
  if(NOT OPENSSL_FOUND)
    set(OPENSSL_USE_STATIC_LIBS OFF)
    find_package(OpenSSL)
  endif()
  if(OPENSSL_FOUND)
    target_compile_definitions(NixStore PRIVATE MLNIX_SHA256_OPENSSL=1)
    target_link_libraries(NixStore PUBLIC OpenSSL::Crypto)
  elseif(MLNIX_SHA256 STREQUAL "openssl")
    message(FATAL_ERROR "MLNIX_SHA256=openssl, but OpenSSL was not found")
  endif()
endif()
# io_uring replay of recorded file accesses (Linux, liburing); elsewhere Prefetch.cpp only records.
find_path(URING_INCLUDE_DIR liburing.h)
find_library(URING_LIBRARY uring)
if(URING_INCLUDE_DIR AND URING_LIBRARY)
  target_compile_definitions(NixStore PUBLIC MLNIX_HAVE_URING=1)
  target_include_directories(NixStore PRIVATE ${URING_INCLUDE_DIR})
  target_link_libraries(NixStore PUBLIC ${URING_LIBRARY} pthread)
endif()
llvm_update_compile_flags(NixStore)
# The hot set of the TrikeShed algebra (include/Composite/Hot.h) is the one precompiled package; scripts/hot-check.sh holds it pure.
target_precompile_headers(NixStore PRIVATE ${PROJECT_SOURCE_DIR}/include/Composite/Hot.h)

# Hollowing the C++ into MLIR (docs/interfaces, scripts/cxx-interfaces.py): an interface's C++ definition is deleted
# (the header keeps the declaration) and provided instead by a lowered .mlir, translated to LLVM IR and compiled to an
# object linked into the owning library.  The .mlir defines the exact mangled symbol with the ABI the extractor gives.
# mlower_interface(TARGET MLIR STEM) is one hollowed interface; adding another is one .mlir under lowered/ and one call.
find_program(MLNIX_MLIR_TRANSLATE mlir-translate HINTS ${LLVM_TOOLS_BINARY_DIR} REQUIRED)
find_program(MLNIX_LOWER_CLANG clang HINTS ${LLVM_TOOLS_BINARY_DIR} REQUIRED)
set(MLNIX_LOWERED_DIR ${CMAKE_CURRENT_BINARY_DIR}/lowered)
file(MAKE_DIRECTORY ${MLNIX_LOWERED_DIR})
function(mlnix_lower_interface target mlir stem)
  if(IS_ABSOLUTE ${mlir})
    set(src ${mlir})
  else()
    set(src ${PROJECT_SOURCE_DIR}/${mlir})
  endif()
  set(ll ${MLNIX_LOWERED_DIR}/${stem}.ll)
  set(o ${MLNIX_LOWERED_DIR}/${stem}.o)
  add_custom_command(OUTPUT ${ll}
    COMMAND ${MLNIX_MLIR_TRANSLATE} --mlir-to-llvmir ${src} -o ${ll}
    DEPENDS ${src} COMMENT "lowering ${mlir} to LLVM IR")
  add_custom_command(OUTPUT ${o}
    COMMAND ${MLNIX_LOWER_CLANG} -O2 -c ${ll} -o ${o}
    DEPENDS ${ll} COMMENT "compiling lowered ${stem}.o")
  add_custom_target(mlnix_lowered_${stem} DEPENDS ${o})
  add_dependencies(${target} mlnix_lowered_${stem})
  target_sources(${target} PRIVATE ${o})
  set_source_files_properties(${o} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
endfunction()
# A hollowed interface written in the TrikeShed dialect (not yet the llvm dialect): first --trikeshed-lower-cursors
# (mlnix-opt), then the stock buffer pipeline mlnixci and the LLVM arm lower with (scripts/nix-native.sh), then translate
# and compile.  Same object linkage as mlnix_lower_interface; the .mlir keeps the algebra in trikeshed ops.
find_program(MLNIX_MLIR_OPT mlir-opt HINTS ${LLVM_TOOLS_BINARY_DIR} REQUIRED)
set(MLNIX_TRIKESHED_PIPELINE
  --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification
  --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine
  --finalize-memref-to-llvm --convert-scf-to-cf --convert-arith-to-llvm --convert-index-to-llvm
  --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts)
# A cross build cannot run the mlnix-opt it makes: MLNIX_HOST_OPT names one built for the build machine from the same
# source (utils/mlnixos-darwin: Linux building for macOS); empty, the default, is this build's own.  The choice is made
# inside the function, because tools/CMakeLists.txt calls it from another directory scope.
set(MLNIX_HOST_OPT "" CACHE FILEPATH "mlnix-opt that runs on the build machine (cross builds); empty = this build's")
function(mlnix_lower_trikeshed target mlir stem)
  if(MLNIX_HOST_OPT)
    set(lower_opt ${MLNIX_HOST_OPT})
  else()
    set(lower_opt $<TARGET_FILE:mlnix-opt>)
  endif()
  set(src ${PROJECT_SOURCE_DIR}/${mlir})
  set(cur ${MLNIX_LOWERED_DIR}/${stem}.cursors.mlir)
  set(low ${MLNIX_LOWERED_DIR}/${stem}.lowered.mlir)
  set(ll ${MLNIX_LOWERED_DIR}/${stem}.ll)
  set(o ${MLNIX_LOWERED_DIR}/${stem}.o)
  add_custom_command(OUTPUT ${cur}
    COMMAND ${lower_opt} ${src} --trikeshed-lower-cursors -o ${cur}
    DEPENDS ${src} mlnix-opt COMMENT "trikeshed-lower-cursors ${mlir}")
  add_custom_command(OUTPUT ${low}
    COMMAND ${MLNIX_MLIR_OPT} ${cur} ${ARGN} ${MLNIX_TRIKESHED_PIPELINE} -o ${low}
    DEPENDS ${cur} COMMENT "lowering ${stem} buffers to llvm")
  add_custom_command(OUTPUT ${ll}
    COMMAND ${MLNIX_MLIR_TRANSLATE} --mlir-to-llvmir ${low} -o ${ll}
    DEPENDS ${low} COMMENT "translating ${stem} to LLVM IR")
  add_custom_command(OUTPUT ${o}
    COMMAND ${MLNIX_LOWER_CLANG} -O2 -Wno-override-module ${MLNIX_LOWER_CLANG_ARGS} -c ${ll} -o ${o}
    DEPENDS ${ll} COMMENT "compiling lowered ${stem}.o")
  add_custom_target(mlnix_lowered_${stem} DEPENDS ${o})
  add_dependencies(${target} mlnix_lowered_${stem})
  target_sources(${target} PRIVATE ${o})
  set_source_files_properties(${o} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
endfunction()
# Composite/Rows.h's row algorithms (findRow, sortRows, uniqueFirst, the union): their own library, linked by every library
# that includes Rows.h (NixStore here, NixFrontend at its definition; NixEval and the tools through them).
add_library(CompositeRows STATIC)
set_target_properties(CompositeRows PROPERTIES LINKER_LANGUAGE CXX)
mlnix_lower_trikeshed(CompositeRows lowered/composite/Rows.mlir Rows)
target_link_libraries(NixStore PUBLIC CompositeRows)
# nixstore::Hash::operator== (lib/Store/Hash.cpp's definition is gone; include/Nix/Store.h keeps the declaration).
mlnix_lower_interface(NixStore lowered/nixstore/HashEq.mlir HashEq)
# nixstore::isInStore (lib/Store/StorePaths.cpp's definition is gone; include/Nix/Store.h keeps the declaration).
mlnix_lower_interface(NixStore lowered/nixstore/IsInStore.mlir IsInStore)
# SHA-512 (lib/Store/Hash.cpp's SHA512Ctx is gone; HashSink keeps the context as plain state and calls these entries) and
# Ed25519 verification (lib/Store/Ed25519.cpp keeps only the ed25519VerifyBase64 bridge).  The compression is a fold over
# each block's 8-byte slices plus scf.for rounds; the padding a combine of a pad slice and a length series, drained; the
# field/point/scalar arithmetic is scf/arith over i64 limb memrefs with trikeshed.fold/compare for the S < L and R checks.
mlnix_lower_trikeshed(NixStore lowered/nixstore/Sha512.mlir Sha512)
# SHA-256 (lib/Store/Hash.cpp's CommonCrypto and llvm::SHA256 contexts are gone; HashSink calls these entries).  Sha256.mlir
# is the Sha512.mlir pattern (update's slices drained into the context, final's padding one combine drained, the digest a
# combineAll) around the rounds of a block, chosen once a process: the CPU's SHA-2 instructions, an llvm-dialect function
# carrying the target feature (Sha256Arm64.mlir: sha256h/h2/su0/su1; Sha256X86.mlir: SHA-NI), the state passed through it
# as two vectors by the loop over the blocks; or the portable rounds, scf loops that clang unrolls whole at the threshold
# below (K folds into the code as immediates, the schedule into registers and stack slots).  The probe is the platform's:
# getauxval on Linux arm64 (Sha256Auxv.mlir), nothing to ask on macOS arm64 (Sha256Apple.mlir), cpuid on x86_64; elsewhere
# the rounds are portable.
set(MLNIX_LOWER_CLANG_ARGS -mllvm -unroll-threshold=4000)
mlnix_lower_trikeshed(NixStore lowered/nixstore/Sha256.mlir Sha256)
unset(MLNIX_LOWER_CLANG_ARGS)
set(MLNIX_SHA256_HW NoHw)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$" AND APPLE)
  set(MLNIX_SHA256_HW Arm64 Apple)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$" AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(MLNIX_SHA256_HW Arm64 Auxv)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$")
  set(MLNIX_SHA256_HW X86)
endif()
foreach(part ${MLNIX_SHA256_HW})
  mlnix_lower_interface(NixStore lowered/nixstore/Sha256${part}.mlir Sha256${part})
endforeach()
# MD5 and SHA-1 (lib/Store/Hash.cpp's llvm::MD5 / llvm::SHA1 contexts are gone; HashSink calls these entries on the same
# 112-byte context shape as SHA-512's).  Each is the Sha512.mlir pattern: block words by trikeshed.fold over 4-byte slices,
# the rounds as scf loops, the padding one combine drained into the context's buffer.
mlnix_lower_trikeshed(NixStore lowered/nixstore/Md5.mlir Md5)
mlnix_lower_trikeshed(NixStore lowered/nixstore/Sha1.mlir Sha1)
mlnix_lower_trikeshed(NixStore lowered/nixstore/Ed25519.mlir Ed25519)
# The byte encoders appendBase16, appendNix32, base64Encode (lib/Store/Hash.cpp's bodies are gone; the bridges size the
# Text and call these entries).  The encoding algebra is trikeshed.series / at / alpha / drain over the byte series.
mlnix_lower_trikeshed(NixStore lowered/nixstore/Encoders.mlir Encoders)
# The pure path algebra of nixstore::baseNameOf / dirOf (StorePaths.cpp's bodies are gone; the bridges size the Text and
# call these entries).  The slash algebra is trikeshed.at / slice / text / drain over the byte series.
mlnix_lower_trikeshed(NixStore lowered/nixstore/PathOps.mlir PathOps)
# The pure store-path naming algebra of nixstore::checkName / outputPathName / isStorePath / storePathName /
# storePathHashPart (StorePaths.cpp's bodies are gone; checkName's bridge keeps the error wording, the others size the
# Text and call these entries).  The naming rules are trikeshed.at / slice / text / compare / combine / drain over the
# byte series; isStorePath calls the IsInStore entry beside it.
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreName.mlir StoreName)
# The prefetch list's row and order algebra (Prefetch.cpp's list reading, mints table, entry order, ring slot driver, line
# and list texts and auto's name are gone; the bridges keep the file I/O, threads, io_uring requests and the owning
# Texts): trikeshed.parts / where / sorted / bisect / combine / combineAll / fold / drain over the list's records.
mlnix_lower_trikeshed(NixStore lowered/nixstore/PrefetchOps.mlir PrefetchOps)
# The pure byte decoders nix32Decode, base64Decode (lib/Store/Hash.cpp's bodies are gone; HashParse.mlir calls them, with
# the room the bridges size and the validity flag they turn into the Maybe).  trikeshed.at over the input series<i8>, a
# constant reverse-alphabet table and guarded byte stores.
mlnix_lower_trikeshed(NixStore lowered/nixstore/Decoders.mlir Decoders)
# The NAR: NarWriter's framing, its walk and restorePath's reader (StorePaths.cpp keeps lstat, the listing, the file's
# bytes, readlink, the PathFilter, the Sink, the writes and the wording as callbacks).  The little-endian prefix, the pad
# and the length+bytes+pad composition are trikeshed.series / slice / combine / drain; the constant NAR tokens are a blob
# + off/len tables read with at; a directory's names are put in byte order by StoreGraph's sorted, each entry's path is
# one combine drained at its parent's end; the reader compares each string with the token expected (compare) and checks
# a name with compare and a fold.
mlnix_lower_trikeshed(NixStore lowered/nixstore/NarFraming.mlir NarFraming)
# The hash-name parser (parseHash with parseRest's prefixes, type checks, length dispatch and digests) and compressHash
# (the XOR fold): lowered/nixstore/HashParse.mlir.  Its nix32 and base64 digests call Decoders.mlir's entries by symbol.
mlnix_lower_trikeshed(NixStore lowered/nixstore/HashParse.mlir HashParse)
# nixstore::jsonFloat (StorePaths.cpp's body is gone; the bridge keeps the snprintf callback and sizes the Text): the
# shortest round-tripping "%.*e" digits (strtod called here) cut by where/alpha/fold, nlohmann's format_buffer cases as
# the extents of one combine of slices (sign, literals, zeros, digits, the exponent's digits) drained once.
mlnix_lower_trikeshed(NixStore lowered/nixstore/JsonFloat.mlir JsonFloat)
# The store-path name algebra of StorePaths.cpp (makeStorePath's fingerprint `type:algo:hex:storeDir:name` and path
# `storeDir/nix32-name`, makeType's `type[:ref]*[:self]`, runProgram's argv pointer fill are gone; the bridges keep
# checkName/compressHash/hashString and the Text sizing).  Each is ONE lazy combine of the pieces drained once into a
# pre-sized buffer (fill-drain); the hex/nix32 digits are the Encoders algebra inlined as a piece.  Store hashes stay
# byte-identical.  The argv fill reads the Text rows' data pointers, allocation-free (it runs in the fork child).
mlnix_lower_trikeshed(NixStore lowered/nixstore/StorePathOps.mlir StorePathOps)
# The derivation ATerm writer nixstore::unparseTo (StorePaths.cpp's composition loop, TextOut/HashOut and the
# escapeInto/appendEscaped helpers are gone; the bridges marshal the Derivation into record arrays, apply maskOutputs
# and slot __json, size the Text and call this entry).  The whole ATerm composition is trikeshed.combineAll / combine /
# slice / text / at / drain over series<i8>: one variadic combine of section views, each list a combineAll, each escaped
# string a combineAll over a constant ATerm escape table, drained once into a pre-sized buffer (fill-drain).
mlnix_lower_trikeshed(NixStore lowered/nixstore/DrvUnparse.mlir DrvUnparse)
# The derivation ATerm reader nixstore::parseDerivation (StorePaths.cpp's ATermParser and its walk are gone; the bridge
# builds the Derivation from the decoded strings, keeping the outputs' kinds, parseHashAlgo/parseHash and their errors,
# __json and the sorted maps).  The walk of the fixed Derive(...) structure is trikeshed.at / slice / compare / drain
# over series<i8> (each run between escapes a slice drained into the room), a failure offset passed through every step.
mlnix_lower_trikeshed(NixStore lowered/nixstore/DrvParse.mlir DrvParse)
# The derivation JSON writer nixstore::derivationToJSON (StorePaths.cpp's composition is gone; the bridge reuses
# marshalDrv's record arrays plus each output's kind).  One variadic trikeshed.combine of literal slices, escaped strings
# (combineAll over Nix's JSON escape table) and list combineAlls, drained once into a pre-sized buffer (fill-drain).
mlnix_lower_trikeshed(NixStore lowered/nixstore/DrvJson.mlir DrvJson)
# structuredAttrsFiles whole (.attrs.json and .attrs.sh; StructuredAttrs.cpp's DOM, parser and shell writer are gone, the
# bridge keeps the record's arrays and the rooms).  __json is read by confix.checked (JsonRead.mlir's
# scan, linked into NixEval), each object's members put in key order by trikeshed.sorted, the placeholders rewritten by a
# combineAll of gaps and paths per pass; each file is ONE combineAll drained once (events / lines of slices and escapes).
mlnix_lower_trikeshed(NixStore lowered/nixstore/StructuredAttrsOps.mlir StructuredAttrsOps)
# The local store's graph and content algorithms (LocalStore.cpp's bodies are gone; the bridges hand the sorted sets over as
# windows and answer the store's reads and writes as callbacks): drvReferences' union (sorted + where), computeFSClosure's
# worklist and visited set (bisect + insert), collectGarbage's dead set and referrer-safe rounds,
# queryPathInfo's lines (parts), contentFingerprint (a fold through XXH3-64, written here) and sameContent's walk.
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreGraph.mlir StoreGraph)
# The local store's index (LocalStore.cpp's allValidPaths, queryReferrers' candidates, queryPathInfo's text, the info
# file's write and unlink are calls): `<stateDir>/info.trie`, the info directory's entries as a trie CAS in TrikeShed's
# shape (HashTrie: rows keyed by the hash part, a byte of fan-out a level, open leaves sealed as sorted, delta-coded
# pages), derived from the info files and checked against the directory before it answers.  It reads the files and the
# directory through the C library; what that does not give under one name and one layout everywhere is the system's
# module (the macOS one is made for the machine: an Intel Mac's 64-bit-inode calls end in $INODE64).
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreIndex.mlir StoreIndex)
if(APPLE)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    set(NIXSI_INODE64 "$INODE64")
  else()
    set(NIXSI_INODE64 "")
  endif()
  configure_file(${PROJECT_SOURCE_DIR}/lowered/nixstore/StoreIndexDarwin.mlir.in ${MLNIX_LOWERED_DIR}/StoreIndexOs.mlir @ONLY)
  mlnix_lower_interface(NixStore ${MLNIX_LOWERED_DIR}/StoreIndexOs.mlir StoreIndexOs)
else()
  mlnix_lower_interface(NixStore lowered/nixstore/StoreIndexLinux.mlir StoreIndexOs)
endif()
# The local store's builder (LocalStore.cpp; the fork, the exec, the walks and the reads stay there): runBuilder's
# environment and argv as one combineAll of `k=v` NUL pieces each, drained once, the pointer table the coordinates;
# scanForReferences' table (the hash parts sorted, the last of equal ones kept) and its scan (32-digit nix32 windows
# bisected into it); registerValidPath's info file as one combine drained once.  runBuilder's placeholders are
# StructuredAttrsOps' rewrite (nixstore_ts_rewrite, through rewritePlaceholders).
mlnix_lower_trikeshed(NixStore lowered/nixstore/BuilderOps.mlir BuilderOps)
# The store's build and add path (LocalStore.cpp's bodies are gone; what calls them names the entries and keeps the
# error an entry returns with).  StoreWords.mlir: every message of the path as data, one combineAll over a message's
# bytes drained once.  StoreWalks.mlir: the trees read and made through the C library (canonicalisePathMetaData,
# copyRecursive, scanForReferences' walk, collectGarbage's roots): a path composed in place (one combine an entry), a
# directory's names a fill read back in order.  What the C library does not give under one name and one layout
# everywhere is the system's module (lstat's answer, errno, the times, waitpid's status, PATH_MAX), made for the machine:
# an Intel Mac's calls end in $INODE64, and st_mode lies where the machine's Linux puts it.
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreWords.mlir StoreWords)
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreWalks.mlir StoreWalks)
# StoreRun.mlir: the processes (runProgram; runBuilder, whose environment is a fill of (name, value) rows drained once in
# name order with the last of equal names kept: sorted, where, one combineAll; builtin:fetchurl), through the C library's
# pipe, fork, execve and waitpid.
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreRun.mlir StoreRun)
# StoreAdd.mlir: what the store gains: addToStore and addTextToStore (a hash, the path it names, the object written,
# made canonical and registered), addPermRoot's links, and realise (a chain of steps, the walks over a derivation's
# outputs, inputs and sources folds with the status carried).
mlnix_lower_trikeshed(NixStore lowered/nixstore/StoreAdd.mlir StoreAdd)
if(APPLE)
  configure_file(${PROJECT_SOURCE_DIR}/lowered/nixstore/StoreBuildDarwin.mlir.in ${MLNIX_LOWERED_DIR}/StoreBuildOs.mlir @ONLY)
else()
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
    set(NIXSB_ST_MODE 24)
  else()
    set(NIXSB_ST_MODE 16)
  endif()
  configure_file(${PROJECT_SOURCE_DIR}/lowered/nixstore/StoreBuildLinux.mlir.in ${MLNIX_LOWERED_DIR}/StoreBuildOs.mlir @ONLY)
endif()
mlnix_lower_interface(NixStore ${MLNIX_LOWERED_DIR}/StoreBuildOs.mlir StoreBuildOs)
# Store.h's sorted rows (SortedSet, SortedMap<V>; the template keeps the storage, the append and the pop): the key's row
# (the halving, trikeshed.compare unsigned on the keys) and the moves of an insert or an erase (a turn of rows [a, b): one
# combine of two slices of the rows' bytes, drained through a room and back).  (allValidPaths' order is the index's.)
mlnix_lower_trikeshed(NixStore lowered/nixstore/SortedRows.mlir SortedRows)
# The crit-bit trie of include/Composite/Patricia.h (its algorithms are gone from the header; the template keeps the
# storage, the value, copy and emit): the leaf walk, the key compare (trikeshed.compare), set's plan and link, prefix's
# byte-order walk.  NixStore owns it; NixEval (Eval.h's tries) links NixStore.
mlnix_lower_trikeshed(NixStore lowered/nixstore/Patricia.mlir Patricia)
# The btrfs ordering cluster (include/Composite/MinMaxHeap.h's heap, pegs and cluster, Funnel.h's level walk: the
# headers keep the inline storage and are bridges, a row crossing as its bytes and its < / == as C callbacks).  The
# heap's push/climb/sift and edge pops, the pegs' argMin, the cluster's insert/min/find/drain, clusterOrder's
# fill-then-drain and Krapivin's put/get walk are scf over the caller's arrays.  NixStore carries it (drvByContent);
# TrikeShedRuntime (trikeshed.cluster_order's kernel, a shared library) links a position-independent copy.
# A row's moves are drains, which lower to block moves: a 16 B row's are constant two-word moves that clang does in
# registers once the row helpers are inlined into the walks (--inline --symbol-dce on the mlir-opt stage: without it
# inode-bench's cluster phase retires 28% more instructions).
mlnix_lower_trikeshed(NixStore lowered/composite/ClusterOps.mlir ClusterOps --inline --symbol-dce)
add_custom_command(OUTPUT ${MLNIX_LOWERED_DIR}/ClusterOps.pic.o
  COMMAND ${MLNIX_LOWER_CLANG} -O2 -fPIC -Wno-override-module -c ${MLNIX_LOWERED_DIR}/ClusterOps.ll -o ${MLNIX_LOWERED_DIR}/ClusterOps.pic.o
  DEPENDS ${MLNIX_LOWERED_DIR}/ClusterOps.ll COMMENT "compiling lowered ClusterOps.pic.o")
set_source_files_properties(${MLNIX_LOWERED_DIR}/ClusterOps.pic.o PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
add_dependencies(TrikeShedRuntime mlnix_lowered_ClusterOps)
target_sources(TrikeShedRuntime PRIVATE ${MLNIX_LOWERED_DIR}/ClusterOps.pic.o)

add_library(NixFrontend STATIC Frontend/Parser.cpp Frontend/Source.cpp Frontend/Confix.cpp)
add_dependencies(NixFrontend MLIRNixOpsIncGen TrikeShedIncGen)
target_link_libraries(NixFrontend PUBLIC MLIRNix MLIRIR CompositeRows)
llvm_update_compile_flags(NixFrontend)
target_precompile_headers(NixFrontend PRIVATE ${PROJECT_SOURCE_DIR}/include/Composite/Hot.h)
# nixfe::canonPath's segment walk (Parser.cpp's body is gone; the bridge sizes the Text and calls this entry).  The walk
# is trikeshed.at / slice / text / drain over the byte series.  NixFrontend owns it: mlnix-parse links NixFrontend alone.
mlnix_lower_trikeshed(NixFrontend lowered/nixfe/CanonPath.mlir CanonPath)
# Parser.cpp's text algorithms (the bodies are gone; the parser keeps bridges): stripIndentation's indent scan and its
# kept segments drained once from one combineAll, parseStringParts' loop driving the grammar actions as callbacks, and
# makePath's lint classification, messages (one combine each) and home path.  NixFrontend owns it, as CanonPath.
mlnix_lower_trikeshed(NixFrontend lowered/nixfe/TextParts.mlir TextParts)
# nixfe::printLiteralString's escaping (Source.cpp's body is gone; the bridge sizes the Text and calls this entry).
# The quoting and per-byte escaping are trikeshed.combineAll / slice / at / text / combine / drain over a constant
# escape table.  NixFrontend owns it: mlnix-parse links NixFrontend alone (Parser.cpp prints string literals too).
mlnix_lower_trikeshed(NixFrontend lowered/nixfe/LiteralString.mlir LiteralString)
# The Nix delimiter scan (nixfe::confix::Bands): lib/Frontend/Confix.cpp's Scanner is gone; the bridge sizes the Bands and
# calls confix_scan_nix, the body of the confix dialect's confix.bands (the character classes as tables, the lexer's
# longest-match rules called back).  NixFrontend carries it (MLIRNix cannot: mlnix-opt links MLIRNix and builds the
# lowered object).  Its state machine is cf blocks: --lift-cf-to-scf structures the loops first
# (--ownership-based-buffer-deallocation takes only structured loops), and --convert-ub-to-llvm reads the poison the lift
# leaves.
mlnix_lower_trikeshed(NixFrontend lowered/nixfrontend/ConfixScan.mlir ConfixScan --lift-cf-to-scf --convert-ub-to-llvm)
# The Nix lexer's token state machine (nixfe::Lexer::nextToken): lib/Frontend/Parser.cpp's next/lexString/lexIndString/
# lexInPath/lexDefault/unescapeStr are gone; the bridge owns the Token, the derived-text pool and the state stack and
# calls nixfe_lex_next (the character classes as tables, the longest-match rules / keyword / number / position called
# back).  Same cf-loop lifting as the Confix scan beside it.
mlnix_lower_trikeshed(NixFrontend lowered/nixfrontend/LexScan.mlir LexScan --lift-cf-to-scf --convert-ub-to-llvm)
# confix::lexBands' band layering (Parser.cpp's token switch and Confix.h's Layers are gone; the bridge lexes the tokens and
# calls nixfe_lb_layers, which adopts the rows): the token actions are two constant tables, and each band close drains its
# pending slice (trikeshed.slice + drain).  NixFrontend owns it: mlnix-parse links NixFrontend alone.
mlnix_lower_trikeshed(NixFrontend lowered/nixfe/BandLayers.mlir BandLayers)

# The Nix sources the evaluator ships (lib/Corepkgs/*.nix: flakes) embedded as <nix/NAME>.
file(GLOB COREPKGS_NIX CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs/*.nix)
set(COREPKGS_INC ${CMAKE_CURRENT_BINARY_DIR}/Corepkgs.inc)
add_custom_command(OUTPUT ${COREPKGS_INC}
  COMMAND ${CMAKE_COMMAND} -DOUT=${COREPKGS_INC} -DDIR=${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs -P ${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs/Embed.cmake
  DEPENDS ${COREPKGS_NIX} ${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs/Embed.cmake
  COMMENT "Corepkgs.inc (embedded Nix sources)")
set_source_files_properties(Eval/Eval.cpp PROPERTIES OBJECT_DEPENDS ${COREPKGS_INC})

add_library(NixEval STATIC Eval/Eval.cpp Eval/Builtins.cpp Eval/StoreBuiltins.cpp Eval/Formats.cpp Eval/EvalModels.cpp)
target_precompile_headers(NixEval PRIVATE ${PROJECT_SOURCE_DIR}/include/Composite/Hot.h)
add_dependencies(NixEval MLIRNixOpsIncGen TrikeShedIncGen)
target_include_directories(NixEval PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(NixEval PUBLIC NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass)
target_link_libraries(NixEval PRIVATE MLIRArithDialect MLIRControlFlowDialect MLIRFuncDialect MLIRLLVMDialect)
llvm_update_compile_flags(NixEval)
# nixev::EvalState::showType (lib/Eval/Eval.cpp's definition is gone; include/Nix/Eval.h keeps the declaration).
mlnix_lower_interface(NixEval lowered/nixeval/ShowType.mlir ShowType)
# The integer checked-arithmetic core of __add/__sub/__mul/__div (the arith template's switch is gone from
# lib/Eval/Builtins.cpp; the bridge keeps the forcing, the int/float dispatch and Nix's error wording).
mlnix_lower_interface(NixEval lowered/nixeval/ArithOps.mlir ArithOps)
# The type predicates __isInt/.../isNull/__isFunction and EvalState::typeOf (the typePred comparisons are gone from
# lib/Eval/Builtins.cpp, typeOf's body from lib/Eval/Eval.cpp; include/Nix/Eval.h keeps the declaration).
mlnix_lower_interface(NixEval lowered/nixeval/TypeOps.mlir TypeOps)
# The list primops __length, __elemAt, __genList, __foldl' (lib/Eval/Builtins.cpp's bodies are gone; the bridges force the
# operands and call these entries).  The list algebra is trikeshed.size / at / series / fold.
mlnix_lower_trikeshed(NixEval lowered/nixeval/ListOps.mlir ListOps)
# The string primops __stringLength, __substring, __concatStringsSep, __replaceStrings and mkStringOf (their bodies are gone
# from lib/Eval/Builtins.cpp and lib/Eval/Eval.cpp; the bridges force/coerce the operands and call these entries).  The text
# algebra is trikeshed.size / slice / compare / combineAll / drain.
mlnix_lower_trikeshed(NixEval lowered/nixeval/StringOps.mlir StringOps)
# The set primops __attrNames, __attrValues, __getAttr, __hasAttr, __intersectAttrs (lib/Eval/Builtins.cpp's bodies are
# gone; the bridges force the operands and call these entries).  The set algebra is trikeshed.sorted / bisect / where /
# alpha / compare / series / drain.
mlnix_lower_trikeshed(NixEval lowered/nixeval/SetOps.mlir SetOps)
# __compareVersions and __splitVersion's component scan (the nextComponent / componentsLT / compareVersions bodies are
# gone).  The version algebra is trikeshed.at / slice / compare / text; the stoll reading's throw stays in the bridge.
mlnix_lower_trikeshed(NixEval lowered/nixeval/VersionOps.mlir VersionOps)
# __sort (the cmp lambda and the sortRows call are gone).  The sort is trikeshed.sorted, stable; each comparison calls
# back into the evaluator (the comparator is a Nix function).
mlnix_lower_trikeshed(NixEval lowered/nixeval/SortOps.mlir SortOps)
# The JSON byte emission: JsonOut::putInt and JsonOut::putString (lib/Eval/Formats.cpp's bodies are gone; the bridges
# reserve room and adopt the drained bytes).  The digits and the escaping are trikeshed.fold / series / combineAll / drain.
mlnix_lower_trikeshed(NixEval lowered/nixeval/PrintOps.mlir PrintOps)
# builtins.fromJSON's reader (include/Composite/Confix.h and Formats.cpp's reifyJSON are gone; parseJSON owns the
# record's arrays and calls this entry, the arena and the error wording stay C++ callbacks).  The checked scan is the
# confix dialect's confix.checked (its body a cf state machine, the open containers a stack in the record); the strings'
# decoding, the numbers' reading and the walk that makes the Values are here, an object's members put in key order by
# trikeshed.sorted / slice / compare unsigned (stable: the last of equal keys kept).
mlnix_lower_trikeshed(NixEval lowered/nixeval/JsonRead.mlir JsonRead --lift-cf-to-scf --convert-ub-to-llvm)
# The value printer's fixed bytes: EvalState::printValue's literals/separators and the TracePrinter's words, the
# integer digits and the elision counts (Eval.cpp's out.put/putInt/elided emission is gone; the bridges reserve room
# and adopt the drained bytes).  The words are trikeshed.slice / text / at / drain over a constant table, the digits a
# fold over the powers of ten, the elision one combine.  The recursion/forcing/seen-table/depth guard stay in Eval.cpp.
mlnix_lower_trikeshed(NixEval lowered/nixeval/PrintValueOps.mlir PrintValueOps)
# The value printer's Attrs/List composition: EvalState::printValue's separator/bracket stitching loops are gone;
# a trikeshed.combineAll of the per-attr/element pieces (rendered once by a caching callback) drained into the Text.
# The recursion/seen-table/depth guard/name sorting stay in Eval.cpp.
mlnix_lower_trikeshed(NixEval lowered/nixeval/PrintCompOps.mlir PrintCompOps)
# The MLNIX_STATS report (EvalState::printStats): every line's composition is one variadic trikeshed.combine of label
# slices, unsigned decimal drains and the float/name windows, drained once into room the bridge reserves; the ranked
# lists and the meta-name join are nested combineAll.  The bridge reads the counters, formats the floats (snprintf),
# ranks the tables and keeps the conditionals and the llvm::errs() write.
mlnix_lower_trikeshed(NixEval lowered/nixeval/StatsOps.mlir StatsOps)
# builtins.toXML's drain: every tag line of the document (the indent, prefix, name, attributes and suffix) is one
# trikeshed.combineAll of the walk's rows, each value a combineAll over a constant escape table or an integer's digits,
# drained once into the bridge's Text.
mlnix_lower_trikeshed(NixEval lowered/nixeval/XmlOps.mlir XmlOps)
# builtins.toXML's walk, the fill (lib/Eval/Formats.cpp's XMLWriter, element stack, toXML/showAttrsXML/posToXML
# recursion and attribute rows are gone): the recursion func.call, the attributes and formals trikeshed.sorted by their
# bytes, one row a tag; the callbacks keep the forcing, copyContext, isDerivation, the seen derivations and positions.
mlnix_lower_trikeshed(NixEval lowered/nixeval/XmlWalk.mlir XmlWalk)
# fromTOML's array close: the open array's elems drained once into the list's cells.
mlnix_lower_trikeshed(NixEval lowered/nixeval/FmtCompOps.mlir FmtCompOps)
# builtins.fromTOML's scan (lib/Eval/Formats.cpp's TomlParser lexing/syntax is gone; the bridge builds the tables from
# its events in order and keeps the duplicate/redefinition checks).  A cf state machine over the input bytes with an
# explicit nesting stack, lifted to scf first; the messages are one trikeshed combine drained once.
mlnix_lower_trikeshed(NixEval lowered/nixeval/TomlScan.mlir TomlScan --lift-cf-to-scf --convert-ub-to-llvm)
# fromTOML's tables (TomlTables.mlir: the scan's events in order build the document's sets and lists, the dotted keys,
# headers, array-of-tables and duplicate checks; Formats.cpp's TomlNode storage, symbols, values and throws are the callbacks).
mlnix_lower_trikeshed(NixEval lowered/nixeval/TomlTables.mlir TomlTables)
# The higher-order list primops __concatLists / __concatMap / __filter / __any / __all / __elem (their C++ loops are
# gone).  concatLists/concatMap are trikeshed.combineAll of the inner lists' cells, filter a trikeshed.where; any/all/elem
# short-circuit in an scf.while.  Each Nix function application calls back into the evaluator.
mlnix_lower_trikeshed(NixEval lowered/nixeval/ListOps2.mlir ListOps2)
# __groupBy / __zipAttrsWith / __partition / __catAttrs / removeAttrs / __listToAttrs / __mapAttrs (their C++ loops are
# gone): the stable grouping by name is trikeshed.sorted over name << 32 | row words and a where of the run starts, the
# selections where / alpha, removeAttrs' membership a bisect, the rows drained into the set.  Each evaluator interaction
# (an application, a forcing, a list or thunk cell, the result set) calls back into Builtins.cpp.
mlnix_lower_trikeshed(NixEval lowered/nixeval/GroupOps.mlir GroupOps)
# __getContext's context algebra: the elements read, sorted by path bytes (trikeshed.sorted / compare unsigned), the
# runs of one path, their flags (fold) and outputs (where).  The sets are made by a callback.
mlnix_lower_trikeshed(NixEval lowered/nixeval/ContextOps.mlir ContextOps)
# The baseNameOf / dirOf primops' slash scans (Builtins.cpp's scans are gone; the bridges coerce and share the window at
# the bounds these entries return).  The scans are trikeshed.at / slice over the byte series.
mlnix_lower_trikeshed(NixEval lowered/nixeval/PathBounds.mlir PathBounds)
# The float->int rounding core of __ceil/__floor (the rounding template's std::ceil/std::floor, range test and cast are
# gone from lib/Eval/Builtins.cpp; the bridge keeps forceValue/forceFloat/mkInt and Nix's error wording).  llvm dialect:
# llvm.intr.ceil / llvm.intr.floor (generic form), the ordered range fcmp and fptosi.
mlnix_lower_interface(NixEval lowered/nixeval/Rounding.mlir Rounding)
# Eval.cpp's error text (appendCodeLines, chomp and the position headers are gone; the bridge reads the source and
# keeps the traces' walk): the "at file:line:col:" line and the code lines around it as one combine and one
# combineAll over the newline offsets (trikeshed.where), and the message's continuation indent, each drained once.
mlnix_lower_trikeshed(NixEval lowered/nixeval/ErrorText.mlir ErrorText)
# __parseDrvName's dash scan (Builtins.cpp's loop is gone; the bridge keeps forceStringNoCtx and the mkString/mkAttrs of
# the two windows).  The first '-' followed by a non-letter is trikeshed.at over the byte series (C-locale isalpha).
mlnix_lower_trikeshed(NixEval lowered/nixeval/DrvNameOps.mlir DrvNameOps)
# derivationStrict's pure algebra (StoreBuiltins.cpp keeps the forcing, the store calls and the throws): the
# outputHashMode / legacy-attribute words, every message as one combineAll of template pieces, the outputs' duplicate
# check over a sorted index series, the context elements sorted, made unique and split, and __structuredAttrs' object.
mlnix_lower_trikeshed(NixEval lowered/nixeval/DrvStrictOps.mlir DrvStrictOps)
# Flake references and toJSON's UTF-8 check (lib/Eval/Formats.cpp's percentDecode/percentEncode/parseQuery/isHexRev/
# putFlakeAttr/parseFlakeRef/flakeRefToString/checkUTF8 bodies are gone; the bridges keep forcing, the throws' wording,
# the values and canonPath).  The splits are trikeshed.parts, the words compare/slice, the parameters sorted, the
# unparsed reference one combine of encoded combineAlls drained once.
mlnix_lower_trikeshed(NixEval lowered/nixeval/FlakeRefOps.mlir FlakeRefOps)
# EvalState::eqValues / lessThan (lib/Eval/Eval.cpp's bodies are gone; the methods forward to these entries).  The type
# dispatch, the int/float cross-comparison, the scalar comparisons and the short-circuiting list/attrs walks are
# trikeshed.at / compare over the cells and bytes, the recursion func.call back into the entries; the callbacks keep
# the forcing, the throws' wording, isDerivation and the outPath lookup.
mlnix_lower_trikeshed(NixEval lowered/nixeval/CmpOps.mlir CmpOps)
# EvalState::coerceToString (lib/Eval/Eval.cpp's body is gone; the method forwards to this entry, errorCtx as raw
# bytes).  The type dispatch, the __toString call / outPath recursion and the list walk with its separator rule are
# here; the callbacks keep the forcing, the TypeError, copyPathToStore, the number text and the element's try/catch
# addTrace.
mlnix_lower_trikeshed(NixEval lowered/nixeval/CoerceOps.mlir CoerceOps)
# EvalState::evalConcatStrings' composition (lib/Eval/Eval.cpp): the per-part int/float accumulation (add + overflow
# test, int->float promotion) and window collection as an scf.for, and the PATH case's concat as a combineAll drained
# once into the Text.  The callbacks keep the forcing/coercion/context merging and the throws' wording; canonPath and
# mkPath stay in the bridge.
mlnix_lower_trikeshed(NixEval lowered/nixeval/ConcatOps.mlir ConcatOps)
# Kursive's walk (include/Composite/Kursive.h detail::walk is gone; matchAll/search forward to this entry).  The
# backtracking state machine over the Step program — checkpoint stack push/pop, step dispatch, the step budget — is one
# scf.while over the caller's arrays; the bridge keeps the primop forcing/coercion, kursiveRun's checkpoint retry,
# pieceOf interning and Nix's error wording.  The pattern compiler is the kursive combinator dialect (--re2mlir reads a
# pattern into combinators, --kursive-to-program generates the Step program from them).  The walk is MLIRNix's: re2mlir
# reads each pattern with it, by the ERE grammar written in the combinators (lowered/kursive/Ere.mlir, compiled once by
# kursive-to-program in-process, so its text is carried in the library).  mlnix-opt links MLIRNix, so the walk (scf,
# memref and llvm ops, no trikeshed) is lowered by mlir-opt alone; NixEval and the tools have it through MLIRNix.
set(KURSIVE_WALK ${MLNIX_LOWERED_DIR}/KursiveOps)
add_custom_command(OUTPUT ${KURSIVE_WALK}.o
  COMMAND ${MLNIX_MLIR_OPT} ${PROJECT_SOURCE_DIR}/lowered/nixeval/KursiveOps.mlir ${MLNIX_TRIKESHED_PIPELINE} -o ${KURSIVE_WALK}.lowered.mlir
  COMMAND ${MLNIX_MLIR_TRANSLATE} --mlir-to-llvmir ${KURSIVE_WALK}.lowered.mlir -o ${KURSIVE_WALK}.ll
  COMMAND ${MLNIX_LOWER_CLANG} -O2 -fPIC -Wno-override-module -c ${KURSIVE_WALK}.ll -o ${KURSIVE_WALK}.o
  DEPENDS ${PROJECT_SOURCE_DIR}/lowered/nixeval/KursiveOps.mlir COMMENT "lowering the kursive walk")
set_source_files_properties(${KURSIVE_WALK}.o PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
target_sources(MLIRNix PRIVATE ${KURSIVE_WALK}.o)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/lowered/kursive/Ere.mlir)
file(READ ${PROJECT_SOURCE_DIR}/lowered/kursive/Ere.mlir KURSIVE_ERE)
file(CONFIGURE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/KursiveEre.inc CONTENT "R\"kursive(@KURSIVE_ERE@)kursive\"\n" @ONLY)
target_include_directories(MLIRNix PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

