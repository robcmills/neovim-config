### telescope improvements

- [ ] ability to edit/copy/dump results list
- [ ] nested lsp references
- [ ] key mapping to toggle telescope find_files whether to find .gitignored files
- [ ] scoped find_files
- [ ] vscode features
- [ ] how to scope a live grep
- [ ] find_files
  * [ ] ignores .dotfiles
  * [ ] should not render files until search is not empty
  * [ ] should debounce?
- [ ] lsp references should group same filepaths


### neovim from scratch

- [x] autocomplete dropdown should show paths for imports
- [x] <leader>h remove highlight
- [x] nvim-tree
  + [ ] auto refresh
  + [x] follow current buffer
  + [x] key mapping to focus file explorer
  + [x] creating a new file/directory in nvim-tree should retain focus (not jump to root) and open new file
  + [x] key mapping to create a new file as sibling to current buffer
    * <leader>n
- [x] bufferline - text_align = left
- [ ] add English dictionary spell checking
- [x] gitlens
  + :Gitsigns blame_line
  + <leader>tb
- [ ] multiple cursors
- [x] close buffer should go to previous buffer or last open buffer, not focus file tree
- [x] key mapping to select all text in the current buffer
  + <leader>A

### neovim

- [x] <Tab> to exit insert mode
- [x] single key page up/down
  + J page down
  + K page up
- [x] single key tab/buffer navigation
  + `T` goes to prev
  + `t` goes to next
  + [ ] can navigate to tab by ordinal number, e.g. <Ctrl-1> goes to first tab
- [x] close all tabs key mapping
  + <leader>C
- yank line, put line should insert row below
  + yy then p
- [x] join lines
  + gJ
- [x] toggle commented code
  + <leader>/ require("Comment.api").toggle_current_linewise()
- [x] hover (show TypeScript type / diagnostics)
  + <leader>k vim.lsp.buf.hover()
- auto absolute imports (if ambiguous, prompt with a list)
  + <leader>la vim.lsp.buf.code_action()
- [ ] build integration - ability to navigate to next/prev error in same file/across all files
  + [d previous diagnostic
  + ]d next diagnostic
  + [ ] should work across project unopened files
- [x] close all folders in file tree
  + W (with nvim-tree focused)
- git integration
  + [ ] view diffs
  + [ ] navigate next/prev diff hunks
  + [ ] commit and push
- [ ] global (project wide) find and replace
- [x] toggle text wrapping
  + :set wrap
  + :set nowrap
  + :set linebreak
  + https://vim.fandom.com/wiki/Word_wrap_without_line_breaks
  + :set textwidth=80
  + :h gq
- [ ] open a new file in the same directory as active buffer
  + <leader>o a (focus neotree then add file/folder)
  + <leader>e a? (focus nvimtree then add file/folder)
- [ ] open a new file in a new window
  + <leader>n
- [x] highlight all occurences of hovered word
  + * to search forward
  + # to search backward
- [ ] show vertical line at 80, 100 columns
  + looks weird
- [x] key mapping to copy file path of current file
  + <leader>yf yank filepath
- [ ] key mapping to sort lines
  + :sort
- [x] folding
  + [ ] how to indent without unfolding
- [x] how to indent without exiting visual mode and losing selection


### astrovim parity

- [x] fix auto indentation
- [ ] should pick up filesystem changes
  + autoread ?
- [x] fix H top of screen and B bottom of screen
- [x] remove margin lines from zt and zb
- [x] show current file path in status line
- [x] fix { and } not navigating to empty lines 
- [x] map s to save all buffers
- [x] diagnostics update_in_insert = false
- [ ] closing all buffers does not open an empty buffer
- [x] lsp references should be a floating window that closes once selected
  + <leader>lR opens Telescope LSP References (but it's broken)
- [x] gitlens
  + gitsigns plugin provides same functionality and more
  + <leader>gl Preview git blame
  + <leader>gp Preview git hunk
- [x] split panes should each have their own bufferline
  + use tmux panes instead of neovim panes to solve this
    <C-b> " Split window vertically
    <C-b> % Split window horizontally
- [x] github copilot
  + [x] figure out tab mapping and collision with nvim-cmp
  + `vim.keymap.set("i", "<C-o>", "<cmd>:lua vim.fn['copilot#Accept']('')<cr>", { desc = "Accept Copilot suggestion" })`
- [ ] lsp
  + [ ] auto import paths not found for third party libraries
  + [x] rename symbol dialog width bug
  + [x] code actions auto import should prefer absolute paths
  + [ ] goto definition ambiguous resolutions should open dialog to select (not a window)
  + [x] filter lsp diagnostics to not show on third party libraries (node_modules)
    * implemented custom on_attach function to manually stop eslint clients that exist in a node_modules workspace

- [ ] bufferline tabs should show full filename
- [x] dynamic width tabs (bufferline)
- [x] show vim mode in text in status bar
- [x] TS and eslint errors in the sidebar "jiggling" pane width
  + Need to set width of gutter as a constant
- [x] adjust color theme to make comments slightly brighter
- [ ] fix autoclose tags


### tmux

- Alacritty key_binding Command + P sends Ctrl-b (tmux prefix)
- <prefix> :resize-pane [-U,D,L,R] [amount]


### alacritty

- [ ] mouse scrolls window not command history


