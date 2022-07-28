return require('packer').startup {
  function(use)
    use 'wbthomason/packer.nvim'

    use 'folke/tokyonight.nvim'

    use {
      'nvim-treesitter/nvim-treesitter',
      run = ':TSUpdate',
      event = { "BufRead", "BufNewFile" },
      cmd = {
        "TSInstall",
        "TSInstallInfo",
        "TSInstallSync",
        "TSUninstall",
        "TSUpdate",
        "TSUpdateSync",
        "TSDisableAll",
        "TSEnableAll",
      },
      config = function()
        require "configs.treesitter"
      end,
    }

    use {
      'kyazdani42/nvim-web-devicons',
      config = function()
        require "configs.icons"
      end,
    }

    use {
      'kyazdani42/nvim-tree.lua',
      requires = {
        'kyazdani42/nvim-web-devicons',
      },
      config = function()
        require "configs.nvim-tree"
      end,
    }

    use {
      'akinsho/bufferline.nvim',
      tag = 'v2.*',
      requires = 'kyazdani42/nvim-web-devicons',
      config = function()
        require 'configs.bufferline'
      end,
    }

    use {
      'nvim-lua/plenary.nvim',
      module = 'plenary',
    }

    use {
      'nvim-telescope/telescope.nvim',
      tag = '0.1.0',
      requires = { { 'nvim-lua/plenary.nvim' } },
      cmd = "Telescope",
      module = "telescope",
      config = function()
        require "configs.telescope"
      end,
    }

    -- Built-in LSP
    use {
      'neovim/nvim-lspconfig',
      event = 'VimEnter',
    }

    -- LSP manager
    use {
      "williamboman/nvim-lsp-installer",
      after = "nvim-lspconfig",
      config = function()
        require "configs.nvim-lsp-installer"
        require "configs.lsp"
      end,
    }

    use {
      'numToStr/Comment.nvim',
      config = function()
        require('Comment').setup()
      end
    }

  end,
  config = {
    display = {
      open_fn = function()
        return require("packer.util").float { border = "rounded" }
      end,
    },
  },
}
