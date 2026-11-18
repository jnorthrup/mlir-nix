{ lib, ... }:
let inherit (lib) mkOption types; in
{
  options = {
    networking.hostName = mkOption {
      type = types.strMatching "[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?";
      default = "mlnix-os";
      description = "Host name, written to /etc/hostname.";
    };
    networking.firewall.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the firewall rules file is rendered.";
    };
    networking.firewall.allowedTCPPorts = mkOption {
      type = types.listOf types.port;
      default = [ 22 ];
      description = "TCP ports accepted by the firewall.";
    };
    time.timeZone = mkOption {
      type = types.enum [ "UTC" "America/Chicago" "America/New_York" "Europe/Berlin" "Asia/Tokyo" ];
      default = "UTC";
      description = "Time zone, written to /etc/timezone.";
    };
    services.motd.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether /etc/motd is rendered.";
    };
    services.motd.text = mkOption {
      type = types.lines;
      default = "mlnix-os";
      description = "Message of the day.";
    };
    services.miniLuci.port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port mini-luci listens on.";
    };
  };
}
