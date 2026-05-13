" tests/minimal_init.vim
set rtp^=.

if isdirectory(expand('~/.local/share/nvim/site/pack/plugins/start/plenary.nvim'))
  set rtp+=~/.local/share/nvim/site/pack/plugins/start/plenary.nvim
elseif isdirectory(expand('~/.local/share/nvim/lazy/plenary.nvim'))
  set rtp+=~/.local/share/nvim/lazy/plenary.nvim
endif

runtime plugin/plenary.vim
