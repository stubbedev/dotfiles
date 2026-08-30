_: {
  flake.modules.homeManager.monitoring =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
      c = pkgs.stubbe.withHash;

      themeName = "catppuccin-mocha";
      themePath = "${config.xdg.configHome}/btop/themes/${themeName}.theme";
    in
    lib.mkIf config.features.desktop {
      programs.btop = {
        enable = true;
        # Not a plain `pkgs.btop`: btop dlopens libnvidia-ml.so for its GPU
        # panel, and a dlopen by soname does not go through glvnd — so it needs
        # the driver libs on the loader path even on NixOS.
        package = gfx.withDriverLibs pkgs.btop;

        themes.${themeName} = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (key: value: ''theme[${key}]="${value}"'') {
            main_bg = c.base;
            main_fg = c.text;
            title = c.text;
            hi_fg = c.blue;
            selected_bg = c.surface1;
            selected_fg = c.blue;
            inactive_fg = c.overlay1;
            graph_text = c.rosewater;
            meter_bg = c.surface1;
            proc_misc = c.rosewater;
            cpu_box = c.mauve;
            mem_box = c.green;
            net_box = c.maroon;
            proc_box = c.blue;
            div_line = c.overlay0;
            temp_start = c.green;
            temp_mid = c.yellow;
            temp_end = c.red;
            cpu_start = c.teal;
            cpu_mid = c.sapphire;
            cpu_end = c.lavender;
            free_start = c.mauve;
            free_mid = c.lavender;
            free_end = c.blue;
            cached_start = c.sapphire;
            cached_mid = c.blue;
            cached_end = c.lavender;
            available_start = c.peach;
            available_mid = c.maroon;
            available_end = c.red;
            used_start = c.green;
            used_mid = c.teal;
            used_end = c.sky;
            download_start = c.peach;
            download_mid = c.maroon;
            download_end = c.red;
            upload_start = c.green;
            upload_mid = c.teal;
            upload_end = c.sky;
            process_start = c.sapphire;
            process_mid = c.lavender;
            process_end = c.mauve;
          }
        );
      };

      # btop rewrites btop.conf whenever a setting is changed in the UI, so it
      # cannot be a store symlink. Rendered from an attrset in btop's own
      stubbe.mutable.".config/btop/btop.conf" = {
        method = "copy";
        source =
          let
            render =
              v:
              if v == true then
                "True"
              else if v == false then
                "False"
              else if builtins.isString v then
                ''"${v}"''
              else
                toString v;
          in
          (pkgs.formats.keyValue { mkKeyValue = k: v: "${k} = ${render v}"; }).generate "btop.conf" {
            color_theme = themePath;
            theme_background = true;
            truecolor = true;
            force_tty = false;
            presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";
            vim_keys = false;
            rounded_corners = false;
            graph_symbol = "braille";
            graph_symbol_cpu = "default";
            graph_symbol_gpu = "default";
            graph_symbol_mem = "default";
            graph_symbol_net = "default";
            graph_symbol_proc = "default";
            shown_boxes = "cpu mem net proc gpu0";
            update_ms = 1000;
            proc_sorting = "memory";
            proc_reversed = false;
            proc_tree = false;
            proc_colors = true;
            proc_gradient = true;
            proc_per_core = true;
            proc_mem_bytes = true;
            proc_cpu_graphs = true;
            proc_info_smaps = false;
            proc_left = false;
            proc_filter_kernel = false;
            proc_aggregate = false;
            cpu_graph_upper = "Auto";
            cpu_graph_lower = "Auto";
            show_gpu_info = "Auto";
            cpu_invert_lower = true;
            cpu_single_graph = false;
            cpu_bottom = false;
            show_uptime = true;
            check_temp = true;
            cpu_sensor = "Auto";
            show_coretemp = true;
            cpu_core_map = "";
            temp_scale = "celsius";
            base_10_sizes = false;
            show_cpu_freq = true;
            clock_format = "%X";
            background_update = true;
            custom_cpu_name = "";
            disks_filter = "";
            mem_graphs = true;
            mem_below_net = false;
            zfs_arc_cached = true;
            show_swap = true;
            swap_disk = true;
            show_disks = true;
            only_physical = true;
            use_fstab = true;
            zfs_hide_datasets = false;
            disk_free_priv = false;
            show_io_stat = true;
            io_mode = false;
            io_graph_combined = false;
            io_graph_speeds = "";
            net_download = 100;
            net_upload = 100;
            net_auto = true;
            net_sync = true;
            net_iface = "";
            base_10_bitrate = "Auto";
            show_battery = true;
            selected_battery = "Auto";
            show_battery_watts = true;
            log_level = "WARNING";
            nvml_measure_pcie_speeds = true;
            rsmi_measure_pcie_speeds = true;
            gpu_mirror_graph = true;
            shown_gpus = "nvidia amd intel apple";
            custom_gpu_name0 = "";
            custom_gpu_name1 = "";
            custom_gpu_name2 = "";
            custom_gpu_name3 = "";
            custom_gpu_name4 = "";
            custom_gpu_name5 = "";
          };
      };
    };
}
