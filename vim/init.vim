" Neovim entry point. Neovim does not read ~/.vimrc, so bridge to the classic
" vimrc linked by the vim topic.
if filereadable(expand('~/.vimrc'))
  source ~/.vimrc
endif
