return require('packer').startup {
  function(use)
    use 'wbthomason/packer.nvim'

    -- colorscheme
    use 'folke/tokyonight.nvim'

    use 'github/copilot.vim'

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
      'akinsho/bufferline.nvim',
      after = 'nvim-web-devicons',
      tag = '*',
      requires = 'nvim-tree/nvim-web-devicons',
      config = function()
        require 'configs.bufferline'
      end,
    }

    use {
      'nvim-lua/plenary.nvim',
      module = 'plenary',
    }

    -- Telescope
    use {
      'nvim-telescope/telescope.nvim',
      tag = '0.1.2',
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

    use {
      'windwp/nvim-autopairs',
      after = 'nvim-treesitter',
      config = function()
        require 'configs.autopairs'
      end,
    }

    use {
      'windwp/nvim-ts-autotag',
      after = 'nvim-treesitter',
      config = function()
        require 'configs.ts-autotag'
      end,
    }

    use {
      'nvim-pack/nvim-spectre',
      requires = { 'nvim-lua/plenary.nvim' },
      config = function()
        require('configs.spectre')
      end,
    }

    use '~/src/nvim-pvg'

    use 'MunifTanjim/nui.nvim'

    use {
      'jackMort/ChatGPT.nvim',
      config = function()
        require('configs.chatgpt')
      end,
      requires = {
        'MunifTanjim/nui.nvim',
        'nvim-lua/plenary.nvim',
        'nvim-telescope/telescope.nvim'
      }
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
