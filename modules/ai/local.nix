# Local models: ollama (CUDA) plus the Crush harness pointed at it.
_:
let
  # Keep the package/model choices shared by the NixOS service, standalone-HM
  # service, Home Manager profile, and Crush config.
  ollamaPackage = pkgs: pkgs.ollama-cuda;
  ollamaModel = "ornith:9b";
  contextWindow = 16384;
  ollamaEnvironment = {
    OLLAMA_CONTEXT_LENGTH = toString contextWindow;
    OLLAMA_FLASH_ATTENTION = "1";
    OLLAMA_KV_CACHE_TYPE = "q8_0";
    OLLAMA_MAX_LOADED_MODELS = "1";
  };
in
{
  flake.modules.nixos.localAi =
    { pkgs, ... }:
    {
      # The NixOS module adds the selected package to systemPackages, owns the
      # daemon, and pulls the declared model in a retrying background unit.
      services.ollama = {
        enable = true;
        package = ollamaPackage pkgs;
        environmentVariables = ollamaEnvironment;
        loadModels = [ ollamaModel ];
      };
    };

  flake.modules.homeManager.localAi =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      ollama = ollamaPackage pkgs;
      inherit (config.stubbe.mcp) servers;
      httpMcpServers = servers.httpServices // servers.proxied;
      crushMcpConfig = lib.optionalString config.features.claudeCode (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: server: ''
            mcp add ${lib.escapeShellArg name} \
              --type http \
              --url ${lib.escapeShellArg "http://${server.host}:${toString server.port}${server.path}"} \
              --header X-Repo-Root "$PWD"
          '') httpMcpServers
        )
      );
    in
    lib.mkIf config.features.development {
      home.packages = [
        ollama
        pkgs.crush
      ];

      # crushrc is the current Crush configuration format. Model weights stay
      # in Ollama's mutable model directory; only their desired identity and
      # harness configuration belong in the Nix store.
      xdg.configFile."crush/crushrc" = {
        force = true;
        text = ''
          provider add ollama \
            --name Ollama \
            --type ollama \
            --base-url "http://127.0.0.1:11434/v1/" \
            --discover-models true

          model add ollama/${ollamaModel} \
            --name "Ornith 9B (local CUDA)" \
            --context-window ${toString contextWindow} \
            --default-max-tokens 4096 \
            --can-reason true

          # Keep thinking disabled by default for responsive agent loops. It
          # remains available because the model is declared can-reason=true.
          model large ollama/${ollamaModel} --max-tokens 4096
          model small ollama/${ollamaModel} --max-tokens 2048

          ${crushMcpConfig}
        '';
      };

      # NixOS owns a system service above. Standalone Home Manager needs the
      # equivalent user service, guarded so the two never bind the same port.
      systemd.user.services = lib.mkIf (config.host.platform != "nixos") {
        ollama = {
          Unit.Description = "Ollama CUDA server for local language models";
          Service = {
            Type = "exec";
            ExecStart = "${ollama}/bin/ollama serve";
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") ollamaEnvironment;
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "default.target" ];
        };

        ollama-model-loader = {
          Unit = {
            Description = "Pull declared Ollama models";
            After = [ "ollama.service" ];
            BindsTo = [ "ollama.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${ollama}/bin/ollama pull ${ollamaModel}";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
