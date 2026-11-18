# The runtime mapping: where an option's value lives in the running system, read by mlnix as text from /proc, /sys and
# /etc.  It reports and writes nothing.  `apply` is the command that would set the running value; only a privileged
# helper could run it, and mini-luci runs unprivileged, so the page shows the command and does not run it.
#   rule loc          null, or how option `loc` maps: { source, live, apply?, range?, agree? } (live is read when
#                     asked; agree, given the configured value, says whether the running system agrees with it: what
#                     agreeing means is the option's, e.g. nix.settings.cores = 0 is every core)
#   entry loc name    the running counterpart of one entry of a mapped attribute set: a unit's cgroup, a user's passwd
#                     line, an /etc file, a sysctl key
#   maps loc          whether `loc` has a rule (cheap: read on every row of the corpus, it reads no file)
# A file that cannot be read stops the whole evaluation (tryEval does not catch it), so only files every user may read
# are read, and the sysctl files that are written, not read, are skipped.
{ lib }:
let
  read = p: if builtins.pathExists p then lib.removeSuffix "\n" (builtins.readFile p) else null;
  rows = s: if s == null then [ ] else lib.filter (l: l != "") (lib.splitString "\n" s);
  fields = l: lib.filter (x: x != "") (lib.splitString " " (lib.replaceStrings [ "\t" ] [ " " ] l));
  int = s: if s == null then null else
    let m = builtins.match "[[:space:]]*(-?[0-9]+)[[:space:]]*" s; in if m == null then s else builtins.fromJSON (lib.head m);
  digits = lib.listToAttrs (lib.imap0 (i: c: lib.nameValuePair c i) (lib.stringToCharacters "0123456789ABCDEF"));
  hex = s: lib.foldl' (a: c: a * 16 + digits.${c}) 0 (lib.stringToCharacters s);

  # TCP ports with a socket listening (/proc/net/tcp and tcp6, state 0A).  WSL's distros share one network namespace,
  # so on mlnixos these are the whole VM's.
  listening = lib.sort lib.lessThan (lib.unique (lib.concatMap (f: lib.concatMap (l:
    let m = builtins.match " *[0-9]+: [0-9A-F]+:([0-9A-F]{4}) [0-9A-F]+:[0-9A-F]{4} 0A .*" l; in
    if m == null then [ ] else [ (hex (lib.head m)) ]) (rows (read f))) [ "/proc/net/tcp" "/proc/net/tcp6" ]));

  swaps = map (l: let f = fields l; at = builtins.elemAt f; in {
    device = at 0; type = at 1; sizeKiB = int (at 2); usedKiB = int (at 3); priority = int (at 4);
  }) (lib.filter (l: builtins.length (fields l) >= 5) (lib.drop 1 (rows (read "/proc/swaps"))));

  cpus = let s = read "/sys/devices/system/cpu/online"; in if s == null then null else
    lib.foldl' (a: r: let m = builtins.match "([0-9]+)-([0-9]+)" r; in
      a + (if m == null then 1 else builtins.fromJSON (builtins.elemAt m 1) - builtins.fromJSON (lib.head m) + 1)) 0
      (lib.splitString "," s);

  # sysctl knobs the option's type does not bound: what the kernel takes (Documentation/admin-guide/sysctl)
  knobs = {
    "vm.swappiness" = [ 0 200 ];
    "vm.dirty_ratio" = [ 0 100 ];
    "vm.dirty_background_ratio" = [ 0 100 ];
    "vm.overcommit_memory" = [ 0 2 ];
    "vm.overcommit_ratio" = [ 0 100 ];
    "vm.vfs_cache_pressure" = [ 0 1000 ];
    "kernel.kptr_restrict" = [ 0 2 ];
    "kernel.dmesg_restrict" = [ 0 1 ];
    "kernel.yama.ptrace_scope" = [ 0 3 ];
    "kernel.pid_max" = [ 301 4194304 ];
    "net.ipv4.ip_forward" = [ 0 1 ];
    "net.ipv4.conf.all.forwarding" = [ 0 1 ];
    "net.ipv6.conf.all.forwarding" = [ 0 1 ];
    "net.core.somaxconn" = [ 0 65535 ];
  };
  writeOnly = k: builtins.match ".*(flush|compact_memory|drop_caches|binfmt_misc.*|cad_pid|usermodehelper.*|stat_refresh)" k != null;
  sysctlFile = k: "/proc/sys/" + lib.replaceStrings [ "." ] [ "/" ] k;
  # a sysctl value as the kernel prints it: NixOS writes false as 0 and true as 1 (config/sysctl.nix)
  sysctlText = v: if v == true then "1" else if v == false then "0" else toString v;
  sysctl = k: rec {
    source = sysctlFile k;
    live = if writeOnly k then null else int (read (sysctlFile k));
    range = knobs.${k} or null;
    apply = "sysctl -w ${k}=<value>";
    agree = c: if c == null || live == null then null else
      lib.concatStringsSep " " (fields (sysctlText c)) == lib.concatStringsSep " " (fields (toString live));
  };

  unit = name:
    let d = "/sys/fs/cgroup/system.slice/${name}.service"; at = f: int (read "${d}/${f}"); in
    if !(builtins.pathExists d) then { source = d; active = false; } else {
      source = d;
      active = true;
      memory = at "memory.current";
      memoryMax = at "memory.max";
      tasks = at "pids.current";
      tasksMax = at "pids.max";
      apply = "systemctl set-property --runtime ${name}.service MemoryMax=<value>";
    };

  passwd = lib.listToAttrs (map (l: let f = lib.splitString ":" l; at = builtins.elemAt f; in
    lib.nameValuePair (at 0) { uid = int (at 2); home = at 5; shell = at 6; })
    (lib.filter (l: builtins.length (lib.splitString ":" l) >= 7) (rows (read "/etc/passwd"))));
  user = name: { source = "/etc/passwd"; exists = passwd ? ${name}; } // (passwd.${name} or { });

  ports = [ [ "services" "miniLuci" "port" ] [ "networking" "firewall" "allowedTCPPorts" ] [ "services" "openssh" "ports" ] ];
  sets = {
    "systemd.services" = "/sys/fs/cgroup/system.slice";
    "users.users" = "/etc/passwd";
    "environment.etc" = "/etc";
    "boot.kernel.sysctl" = "/proc/sys";
  };
in
rec {
  inherit knobs;

  rule = loc:
    let p = lib.concatStringsSep "." loc; in
    if loc == [ "networking" "hostName" ] then rec {
      source = "/proc/sys/kernel/hostname";
      live = read "/proc/sys/kernel/hostname";
      apply = "hostname <value>";
      agree = c: c == live;
    }
    else if builtins.length loc == 4 && lib.take 3 loc == [ "boot" "kernel" "sysctl" ] then sysctl (lib.last loc)
    else if sets ? ${p} then { source = sets.${p}; perEntry = true; }
    else if loc == [ "swapDevices" ] then {
      source = "/proc/swaps";
      live = swaps;
      # the configured devices are the ones swapping, and no other is
      agree = c: let devs = map (s: s.device) swaps; in
        builtins.length c == builtins.length devs && lib.all (d: builtins.elem (d.device or "") devs) c;
    }
    else if loc == [ "boot" "kernelParams" ] then rec {
      source = "/proc/cmdline";
      live = lib.filter (s: s != "") (lib.splitString " " (read "/proc/cmdline"));
      # every configured parameter is on the running kernel's command line
      agree = c: lib.all (p: builtins.elem p live) c;
    }
    else if loc == [ "boot" "kernelPackages" ] then
      { source = "/proc/sys/kernel/osrelease"; live = read "/proc/sys/kernel/osrelease"; }
    else if builtins.elem loc ports then {
      source = "/proc/net/tcp, /proc/net/tcp6 (listening)";
      live = listening;
      # a port the configuration names has a socket listening on it
      agree = c: lib.all (p: builtins.elem p listening) (lib.toList c);
    }
    else if loc == [ "nix" "settings" "cores" ] then {
      source = "/sys/devices/system/cpu/online";
      live = cpus;
      agree = c: c == 0 || c == cpus;  # 0: every core
    }
    else if loc == [ "nix" "settings" "max-jobs" ] then {
      source = "/sys/devices/system/cpu/online";
      live = cpus;
      agree = c: c == "auto" || c == cpus;
    }
    else null;

  maps = loc: rule loc != null;

  entry = loc: name:
    let p = lib.concatStringsSep "." loc; in
    if p == "systemd.services" then unit name
    else if p == "users.users" then user name
    else if p == "environment.etc" then { source = "/etc/${name}"; exists = builtins.pathExists "/etc/${name}"; }
    else if p == "boot.kernel.sysctl" then sysctl name
    else null;
}
