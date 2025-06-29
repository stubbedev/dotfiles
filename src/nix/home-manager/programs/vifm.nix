{ ... }: {
  programs.vifm = {
    enable = true;
    extraConfig = ''
      " palenight color scheme for vifm

      " Reset all styles first
      highlight clear

      highlight Border	cterm=none	ctermfg=default	ctermbg=default

      highlight TopLine	cterm=none	ctermfg=002	ctermbg=default
      highlight TopLineSel	cterm=bold	ctermfg=002	ctermbg=default

      highlight Win		cterm=none	ctermfg=251	ctermbg=default
      highlight Directory	cterm=bold	ctermfg=004	ctermbg=default
      highlight CurrLine	cterm=bold,inverse	ctermfg=default	ctermbg=default
      highlight OtherLine	cterm=bold	ctermfg=default	ctermbg=default
      highlight Selected	cterm=none	ctermfg=003	ctermbg=008

      highlight JobLine	cterm=bold	ctermfg=251	ctermbg=008
      highlight StatusLine	cterm=none	ctermfg=008	ctermbg=default
      highlight ErrorMsg	cterm=bold	ctermfg=001	ctermbg=default
      highlight WildMenu	cterm=bold	ctermfg=015	ctermbg=008
      highlight CmdLine	cterm=none	ctermfg=007	ctermbg=default

      highlight Executable	cterm=bold	ctermfg=002	ctermbg=default
      highlight Link		cterm=bold	ctermfg=006	ctermbg=default
      highlight BrokenLink	cterm=bold	ctermfg=001	ctermbg=default
      highlight Device	cterm=bold,standout	ctermfg=000	ctermbg=011
      highlight Fifo		cterm=none	ctermfg=003	ctermbg=default
      highlight Socket	cterm=bold	ctermfg=005	ctermbg=default
    '';
  };
}
