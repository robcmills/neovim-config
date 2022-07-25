return require('packer').startup(function()
  use 'wbthomason/packer.nvim'

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
    event = "VimEnter",
    config = function()
      require "configs.icons"
    end,
  }

  use 'folke/tokyonight.nvim'

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
    requires = { {'nvim-lua/plenary.nvim'} },
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
end)
