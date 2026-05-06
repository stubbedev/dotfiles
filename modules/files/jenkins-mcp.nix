_: {
  flake.modules.homeManager.filesJenkinsMcp =
    {
      config,
      homeLib,
      ...
    }:
    {
      # secrets/jenkins-mcp is the raw JSON config the @stubbedev/jenkins-mcp
      # server reads at startup. Edit with: hm secret edit jenkins-mcp
      sops.secrets.jenkins_mcp = homeLib.mkBinarySecret {
        name = "jenkins-mcp";
        path = "${config.home.homeDirectory}/.jenkins-mcp.json";
      };
    };
}
