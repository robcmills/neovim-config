return require('packer').startup {
  function(use)
    use 'wbthomason/packer.nvim'

    -- colorscheme
    use 'folke/tokyonight.nvim'

    use {
      'nvim-treesitter/nvim-treesitter',
      run = ':TSUpdate',
      event = { 'BufRead', 'BufNewFile' },
      cmd = {
        'TSInstall',
        'TSInstallInfo',
        'TSInstallSync',
        'TSUninstall',
        'TSUpdate',
        'TSUpdateSync',
        'TSDisableAll',
        'TSEnableAll',
      },
      config = function()
        require 'configs.treesitter'
      end,
    }

    use 'nvim-tree/nvim-web-devicons'

    -- File Tree
    use {
      'nvim-tree/nvim-tree.lua',
      after = 'nvim-web-devicons',
      requires = {
        'nvim-tree/nvim-web-devicons',
      },
      config = function()
        require 'configs.nvim-tree'
      end,
    }

    use {
      'nvim-lua/plenary.nvim',
      module = 'plenary',
    }

    -- Telescope

    use {
      'nvim-telescope/telescope-fzf-native.nvim',
      run = 'make'
    }

    use {
      'nvim-telescope/telescope.nvim',
      tag = '0.1.8',
      requires = { { 'nvim-lua/plenary.nvim' } },
      cmd = 'Telescope',
      module = 'telescope',
      config = function()
        require 'configs.telescope'
      end,
    }

    -- LSP
    use {
      'neovim/nvim-lspconfig',
      config = function()
        require 'configs.lsp'
      end,
    }

    -- Completion engine
    use {
      'hrsh7th/nvim-cmp',
      config = function()
        require 'configs.cmp'
      end,
    }

    -- Snippet completion sources
    use { 'hrsh7th/cmp-nvim-lsp', after = 'nvim-cmp' }
    use { 'hrsh7th/cmp-buffer', after = 'nvim-cmp' }
    use { 'hrsh7th/cmp-cmdline', after = 'nvim-cmp' }
    use { 'hrsh7th/cmp-git', after = 'nvim-cmp' }
    use { 'hrsh7th/cmp-path', after = 'nvim-cmp' }
    use { 'saadparwaiz1/cmp_luasnip', after = 'nvim-cmp' }
    use { 'L3MON4D3/LuaSnip', after = 'nvim-cmp' }

    -- Comment
    use {
      'numToStr/Comment.nvim',
      config = function()
        require('Comment').setup()
      end
    }

    -- Git integrations
    use {
      'lewis6991/gitsigns.nvim',
      event = 'BufEnter',
      config = function()
        require 'configs.gitsigns'
      end,
    }

    use {
      'sindrets/diffview.nvim',
      config = function()
        require('configs.diffview')
      end,
    }

    use 'tpope/vim-fugitive'

    -- Statusline
    use {
      'feline-nvim/feline.nvim',
      after = 'nvim-web-devicons',
      config = function()
        require 'configs.feline'
      end,
    }

    -- use '~/src/nvim-pvg' -- personalized vim grep

    use 'MunifTanjim/nui.nvim'

    -- dadbod (database client)
    use 'tpope/vim-dadbod'
    use 'kristijanhusak/vim-dadbod-completion'
    use 'kristijanhusak/vim-dadbod-ui'

    -- disabled while I try supermaven
    -- use 'github/copilot.vim'

    use {
      'supermaven-inc/supermaven-nvim',
      config = function()
        require('configs.maven')
      end,
    }

    use {
      'MeanderingProgrammer/render-markdown.nvim',
      ft = { 'markdown' },
      after = { 'nvim-treesitter' },
      requires = { 'nvim-tree/nvim-web-devicons', opt = true },
      config = function()
        require('render-markdown').setup({
          file_types = { 'markdown' },
        })
      end,
    }

    use {
      'stevearc/dressing.nvim',
      config = function()
        require('dressing').setup({
          input = {
            relative = 'editor',
          },
        })
      end,
    }

    use 'mustache/vim-mustache-handlebars'

    use {
      '/Users/robcmills/src/prompt.nvim',
      config = function()
        require('prompt').setup()
      end,
    }

  end,
  config = {
    display = {
      open_fn = function()
        return require('packer.util').float { border = 'rounded' }
      end,
    },
  },
}
