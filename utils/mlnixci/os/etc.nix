{ lib, config, ... }:
let inherit (lib) mkOption types mkIf; in
{
  options.etc = mkOption {
    type = types.attrsOf types.str;
    internal = true;
    description = "Files under /etc: name to content.";
  };
  config.etc = lib.mkMerge [
    {
      hostname = config.networking.hostName + "\n";
      timezone = config.time.timeZone + "\n";
    }
    (mkIf config.services.motd.enable { motd = config.services.motd.text + "\n"; })
    (mkIf config.networking.firewall.enable {
      "mini-luci/firewall.rules" = lib.concatMapStrings (p: "-A INPUT -p tcp --dport ${toString p} -j ACCEPT\n")
        config.networking.firewall.allowedTCPPorts;
    })
  ];
}
