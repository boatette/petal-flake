self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.petal;
  tomlFormat = pkgs.formats.toml { };

  settings = cfg.settings // {
    data_dir = cfg.dataDir;
  };
  configFile = tomlFormat.generate "petal.toml" settings;

  # The gallery's folders: petal reads them, moves deleted pictures into their .trash, and
  # watches them for new ones.
  outputs = lib.attrValues (cfg.settings.comfyui.outputs or { });
  writable = [ cfg.dataDir ] ++ outputs;

  tailscale = lib.getExe config.services.tailscale.package;
in
{
  options.services.petal = {
    enable = lib.mkEnableOption "petal, a phone UI for ComfyUI's text-to-picture workflows";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.petal;
      defaultText = lib.literalExpression "petal.packages.\${system}.petal";
      description = "The petal package to use";
    };

    user = lib.mkOption {
      type = lib.types.str;
      example = "alice";
      description = "The user petal runs as. It needs to read and write the gallery's folder, and polkit has to let it start and stop ComfyUI's unit (settings.comfyui.unit)";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "The group petal runs as";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/petal";
      example = "/home/alice/.local/share/petal";
      description = "Where the database (and a daily snapshot of it, for backups) and the push key are kept";
    };

    tailscale = {
      enable = lib.mkEnableOption "serving petal to the tailnet over HTTPS with `tailscale serve` (needs HTTPS certificates turned on in the Tailscale admin console)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
        description = "The tailnet HTTPS port petal is served on";
      };
    };

    settings = lib.mkOption {
      default = { };
      example = lib.literalExpression ''
        {
          catalog = ./petal-catalog.json;
          comfyui = {
            url = "http://127.0.0.1:8188";
            unit = "comfyui.service";
            idle_stop_minutes = 20;
            outputs.image = "/home/alice/Pictures/ComfyUI";
          };
          llm.url = "http://127.0.0.1:8080/v1";
        }
      '';
      description = "petal's config.toml; see config.example.toml for every setting";
      type = lib.types.submodule {
        freeformType = tomlFormat.type;

        options = {
          listen = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1:8190";
            description = "The address petal listens on";
          };

          catalog = lib.mkOption {
            type = lib.types.path;
            description = "The workflow catalog (JSON) petal offers";
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.group} -"
    ]
    ++ map (dir: "d ${dir} 0755 ${cfg.user} ${cfg.group} -") outputs;

    systemd.services.petal = {
      description = "petal, a phone UI for ComfyUI";
      documentation = [ "https://github.com/boatette/petal-flake" ];
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      # To start and stop ComfyUI's unit.
      path = [ config.systemd.package ];

      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --config ${configFile}";
        User = cfg.user;
        Group = cfg.group;
        # Thumbnails go in /var/cache/petal.
        StateDirectory = "petal";
        CacheDirectory = "petal";
        Restart = "on-failure";
        RestartSec = 5;

        # Nothing but its own data and the gallery's folders is writable, and of home only
        # those are visible at all.
        ProtectSystem = "strict";
        ProtectHome = "tmpfs";
        BindPaths = writable;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" ];
        SystemCallArchitectures = "native";
        # systemctl reaches systemd over D-Bus, a Unix socket.
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        UMask = "0077";
      };
    };

    # https://<host>.<tailnet>.ts.net, while petal itself stays on 127.0.0.1. Not tied to
    # tailscaled's lifetime: tailscaled keeps the serve config across its own restarts, and a
    # stop of tailscaled (at suspend, say) mustn't remove it.
    systemd.services.petal-tailscale = lib.mkIf cfg.tailscale.enable {
      description = "Serve petal to the tailnet";
      after = [
        "tailscaled.service"
        "petal.service"
      ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Fails until the machine has logged in to Tailscale and HTTPS is turned on.
        Restart = "on-failure";
        RestartSec = 60;
        ExecStart = "${tailscale} serve --bg --https=${toString cfg.tailscale.port} http://${cfg.settings.listen}";
        ExecStop = "${tailscale} serve --https=${toString cfg.tailscale.port} off";
      };
    };
  };
}
