# Binary caches, in Nix: a store path that a cache holds is fetched instead of built.  Embedded as <nix/substitute.nix>.
#
#   (import <nix/substitute.nix>) { }                       caches and keys from MLNIX_SUBSTITUTERS / MLNIX_TRUSTED_KEYS (or caches =, keys =)
#     .substitute PATH      fetch PATH and its references; true when PATH is valid afterwards
#     .ensure DRVPATH       make a derivation's outputs valid from the caches where they are, else its inputs'
#
# A cache serves <cache>/<hash>.narinfo (the NAR's URL, compression, NarHash, NarSize, References, Sig) and the NAR.
# What this file asks of the host: curl and the decompressor (procRun), the NAR restore with its hash check
# (storeImportNar) and the Ed25519 check (cryptoVerify).
{ caches ? null, keys ? null }:
let
  inherit (builtins) all any concatMap concatStringsSep elemAt filter fromJSON getEnv head isString listToAttrs mapAttrs match
    attrNames attrValues sort split substring baseNameOf seq;
  inherit (builtins) cryptoVerify fsUnlink procRun storeDerivation storeImportNar storeValid;

  words = s: filter (w: isString w && w != "") (split " " s);
  # MLNIX_SUBSTITUTERS names the caches (space separated; `none` for none), MLNIX_TRUSTED_KEYS the keys as name:base64
  cacheList =
    if caches != null then caches
    else let v = getEnv "MLNIX_SUBSTITUTERS"; in if v == "" then [ "https://cache.nixos.org" ] else if v == "none" then [ ] else words v;
  keyList =
    if keys != null then keys
    else let v = getEnv "MLNIX_TRUSTED_KEYS"; in if v == "" then [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ] else words v;

  storeDir = builtins.storeDir;
  tmp = let t = getEnv "TMPDIR"; in if t == "" then "/tmp" else t;
  run = prog: args: procRun { inherit prog args; };

  # the `Key: value` lines of a narinfo
  fieldsOf = text:
    listToAttrs (concatMap
      (l: let m = match "([A-Za-z]+): (.*)" l; in if m == null then [ ] else [{ name = head m; value = elemAt m 1; }])
      (filter isString (split "\n" text)));
  sigsOf = text: concatMap (l: let m = match "Sig: (.*)" l; in if m == null then [ ] else [ (head m) ]) (filter isString (split "\n" text));

  # what Nix signs: 1;path;narHash;narSize;references (full paths, sorted, comma separated)
  fingerprint = path: i: refs: "1;${path};${i.NarHash};${i.NarSize};${concatStringsSep "," (sort (a: b: a < b) refs)}";
  signedBy = fp: sig:
    let m = match "([^:]+):(.*)" sig; in
    m != null && any (k: let km = match "([^:]+):(.*)" k; in km != null && head km == head m && cryptoVerify { sig = elemAt m 1; message = fp; key = elemAt km 1; }) keyList;

  unpacker = c: { xz = "xz -dc"; zstd = "zstd -dc"; bzip2 = "bzip2 -dc"; none = "cat"; }.${c} or null;

  substitute = path: storeValid path || any (cache: fromCache cache path) cacheList;

  fromCache = cache: path:
    let
      hashPart = substring 0 32 (baseNameOf path);
      info = run "curl" [ "-fsL" "--retry" "2" "${cache}/${hashPart}.narinfo" ]; # a 404 is the ordinary miss
      text = info.stdout;
      i = fieldsOf text;
      refs = map (r: "${storeDir}/${r}") (words (i.References or ""));
      packed = "${tmp}/mlnix-${hashPart}.nar.packed";
      nar = "${tmp}/mlnix-${hashPart}.nar";
      sh = unpacker (i.Compression or "bzip2");
      download = run "curl" [ "-fsL" "--retry" "3" "-o" packed "${cache}/${i.URL}" ];
      unpack = run "sh" [ "-c" "${sh} < \"$0\" > \"$1\"" packed nar ];
      fetched = download.status == 0 && unpack.status == 0
        && (seq (storeImportNar { inherit path nar; narHash = i.NarHash; references = refs; deriver = if (i.Deriver or "unknown-deriver") == "unknown-deriver" then "" else "${storeDir}/${i.Deriver}"; ca = i.CA or ""; }) true);
    in
    info.status == 0
    && (i.StorePath or "") == path
    && sh != null
    && any (signedBy (fingerprint path i refs)) (sigsOf text)
    && all substitute (filter (r: r != path) refs) # the closure first: a path is never valid with part of it missing
    && seq fetched (seq (fsUnlink packed) (seq (fsUnlink nar) fetched));

  # A derivation's outputs from the caches where they are there; where not, its inputs from them, so that building it builds only the rest.
  ensure = drvPath:
    let d = (fromJSON (storeDerivation drvPath)).${drvPath}; in
    all (o: o ? path && o.path != "" && storeValid o.path) (attrValues d.outputs)
    || all (o: o ? path && o.path != "" && substitute o.path) (attrValues d.outputs)
    || (all ensure (attrNames d.inputDrvs) && all substitute d.inputSrcs);
in
{ inherit substitute ensure; }
