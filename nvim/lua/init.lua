vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking text',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function ()
        vim.highlight.on_yank()
    end,
})
require("core.mappings")
require('config.lazy')
vim.g.loaded_netrw = 0
vim.g.loaded_netrwPlugin = 0
vim.keymap.set("n", "<Esc>", "<cmd>noh<CR>")
vim.cmd 'set expandtab'
vim.cmd 'set tabstop=4'
vim.cmd 'set shiftwidth=4'

