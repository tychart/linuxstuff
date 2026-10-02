set nocompatible

syntax on
if has('autocmd')
  filetype plugin indent on
endif

" Basic editing and search defaults.
set number
set showcmd
set ruler
set wildmenu

if exists('&wildmode')
  set wildmode=longest:full,full
endif

set lazyredraw
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set backspace=indent,eol,start
set autoindent
set expandtab
set tabstop=2
set shiftwidth=2

if exists('&softtabstop')
  set softtabstop=2
endif

set mouse=a
set hidden
set splitbelow
set splitright
set scrolloff=3
set history=1000
set noerrorbells
set visualbell
set laststatus=2
set cursorline

" Terminal cursor shapes: blinking block in Normal, blinking bar in Insert,
" blinking underline in Replace. Terminal support may vary.
let &t_SI = "\<Esc>[5 q"
let &t_SR = "\<Esc>[3 q"
let &t_EI = "\<Esc>[1 q"

" Save undo history on disk so undo still works after reopening a file.
if has('persistent_undo')
  set undodir=~/.vim/undodir
  set undofile
  set undolevels=1000
  set undoreload=10000
endif

" F6 toggles the highlighted current line. Double-Esc clears search highlighting.
nnoremap <silent> <F6> :set cursorline!<CR>
inoremap <silent> <F6> <C-o>:set cursorline!<CR>
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" Use space as the leader key for custom shortcuts.
if !exists('mapleader')
  let mapleader = ' '
endif

" OSC 52 lets Vim copy over SSH/remote terminals without needing a local clipboard provider.
" <leader>c copies the current motion or visual selection.
nmap <leader>c <Plug>OSCYankOperator
nmap <leader>cc <leader>c_
vmap <leader>c <Plug>OSCYankVisual

" Reopen files at the last cursor position from the previous edit session.
augroup setupconfig_vim_startup
  autocmd!
  autocmd BufReadPost *
    \ if line("'\"") > 0 && line("'\"") <= line('$') && &filetype !~# 'commit' |
    \   execute 'normal! g' . nr2char(96) . '"' |
    \ endif
augroup END
