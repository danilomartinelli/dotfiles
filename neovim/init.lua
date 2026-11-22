-- Neovim is the editor every shell opens: $EDITOR, $VISUAL and Git all name
-- it, locally and over SSH. It is configured for that job, editing one file
-- well, and nothing here turns it into an IDE; Zed is the one opened on
-- purpose for a project.

local opt = vim.opt

opt.number = true
opt.clipboard = 'unnamedplus'
-- Undo history survives closing the file. Neovim keeps it under its own state
-- directory, so no path is set here.
opt.undofile = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.ignorecase = true
opt.smartcase = true

-- The one plugin: Neovim bundles Catppuccin's Latte and Mocha, and every
-- other tool on this machine is on Macchiato. nvim-pack-lock.json beside this
-- file records the revision, and is linked from the repository like this file.
--
-- A commit message must still open when the plugin cannot be fetched, so a
-- failure here falls back to a bundled colorscheme instead of stopping.
local themed = pcall(function()
  vim.pack.add({ { src = 'https://github.com/catppuccin/nvim', name = 'catppuccin' } }, { confirm = false })
  require('catppuccin').setup({ flavour = 'macchiato' })
  vim.cmd.colorscheme('catppuccin')
end)
if not themed then
  vim.cmd.colorscheme('habamax')
end
