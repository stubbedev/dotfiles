# Local LLM inference via Ollama (Vulkan acceleration), wired into Harness as an
# OpenAI-compatible provider. Desktop-only: the NixOS service runs the daemon
# and auto-pulls the model; the home-manager half just teaches Harness where to
# find it. On a non-NixOS desktop the provider config is harmless (Harness will
# fail to connect until the user starts an ollama serve themselves), and on a
# headless host neither half activates.
_: {
  flake.modules.nixos.ollama =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.desktop {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-vulkan;
        loadModels = [ "ornith-1.5:9b" ];
      };
    };

  flake.modules.homeManager.ollama =
    {
      config,
      lib,
      ...
    }:
    lib.mkIf (config.features.desktop && config.features.harness) {
      stubbe.harness.providers.ollama = {
        type = "openai-compat";
        base_url = "http://localhost:11434/v1";
        api_key = "ollama";
        models = [
          {
            id = "ornith-1.5:9b";
            name = "Ornith 1.5 9B";
            context_window = 262144;
            can_reason = true;
            supports_attachments = true;
          }
        ];
      };
    };
}
