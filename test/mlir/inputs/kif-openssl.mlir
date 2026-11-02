// The scenario of nix_sumo.md section 18, as a theory: an advisory on openssl reaches curl and nginx; nginx is a running
// service. The facts are sumo ops; the four rules are kif terms. Lowered by sumo-to-kif and kif-to-nix, mlnix gives the
// facts and rules to the solver (sumo-nix/datalog.nix).
kif.theory @openssl {
  sumo.instance "hello" "NIXPackage"
  sumo.instance "curl" "NIXPackage"
  sumo.instance "nginx" "NIXPackage"
  sumo.instance "nginx" "NIXService"
  sumo.instance "glibc" "NIXPackage"
  sumo.instance "openssl" "NIXPackage"
  sumo.instance "app" "NIXPackage"
  sumo.holds "dependsOn" ["curl", "openssl"]
  sumo.holds "dependsOn" ["nginx", "openssl"]
  sumo.holds "dependsOn" ["hello", "glibc"]
  sumo.holds "dependsOn" ["app", "curl"]
  sumo.holds "vulnerable" ["openssl", "CVE-2026-9999"]
  sumo.holds "severity" ["CVE-2026-9999", "critical"]
  sumo.holds "serviceState" ["nginx", "running"]

  %and = kif.atom "and"
  %dependsOn = kif.atom "dependsOn"
  %transitive = kif.atom "dependsOnTransitive"
  %vulnerable = kif.atom "vulnerable"
  %instance = kif.atom "instance"
  %severity = kif.atom "severity"
  %serviceState = kif.atom "serviceState"
  %violation = kif.atom "policyViolation"
  %package = kif.atom "NIXPackage"
  %service = kif.atom "NIXService"
  %critical = kif.atom "critical"
  %running = kif.atom "running"
  %policy = kif.atom "NoCriticalRunningCVE"
  %a = kif.var "?a"
  %b = kif.var "?b"
  %c = kif.var "?c"
  %pkg = kif.var "?pkg"
  %dep = kif.var "?dep"
  %cve = kif.var "?cve"

  // (=> (and (dependsOn ?a ?b) (dependsOn ?b ?c)) (dependsOnTransitive ?a ?c))
  %ab = kif.list(%dependsOn, %a, %b)
  %bc = kif.list(%dependsOn, %b, %c)
  %ac = kif.list(%transitive, %a, %c)
  %chain = kif.list(%and, %ab, %bc)
  kif.rule %chain implies %ac

  // (=> (dependsOn ?a ?b) (dependsOnTransitive ?a ?b))
  %ab2 = kif.list(%transitive, %a, %b)
  kif.rule %ab implies %ab2

  // (=> (and (instance ?pkg NIXPackage) (dependsOnTransitive ?pkg ?dep) (vulnerable ?dep ?cve)) (vulnerable ?pkg ?cve))
  %isPackage = kif.list(%instance, %pkg, %package)
  %reaches = kif.list(%transitive, %pkg, %dep)
  %depVulnerable = kif.list(%vulnerable, %dep, %cve)
  %pkgVulnerable = kif.list(%vulnerable, %pkg, %cve)
  %spread = kif.list(%and, %isPackage, %reaches, %depVulnerable)
  kif.rule %spread implies %pkgVulnerable

  // (=> (and (vulnerable ?pkg ?cve) (severity ?cve critical) (instance ?pkg NIXService) (serviceState ?pkg running))
  //     (policyViolation ?pkg NoCriticalRunningCVE))
  %isCritical = kif.list(%severity, %cve, %critical)
  %isService = kif.list(%instance, %pkg, %service)
  %isRunning = kif.list(%serviceState, %pkg, %running)
  %breach = kif.list(%violation, %pkg, %policy)
  %policyBody = kif.list(%and, %pkgVulnerable, %isCritical, %isService, %isRunning)
  kif.rule %policyBody implies %breach
}
