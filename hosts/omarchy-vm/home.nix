# hosts/omarchy-vm/home.nix
# Home-manager configuration for Omarchy VM dev user
{ config, pkgs, lib, ... }:

{
  home.username = "dev";
  home.homeDirectory = "/home/dev";
  home.stateVersion = "23.11";

  # Import shared modules
  imports = [
    # Cross-platform modules
    ../../modules/home-manager/apps/git.nix
    ../../modules/home-manager/apps/tmux.nix
    ../../modules/home-manager/shell/direnv.nix

    # Linux-specific fish configuration
    ../../modules/nixos/fish.nix

    # Terminal emulator
    ../../modules/home-manager/apps/ghostty.nix
  ];

  # Override Ghostty for Linux
  programs.ghostty = {
    settings = {
      # Linux-specific keybindings
      keybind = [
        "ctrl+shift+c=copy_to_clipboard"
        "ctrl+shift+v=paste_from_clipboard"
        "ctrl+shift+t=new_tab"
        "ctrl+shift+w=close_surface"
        "ctrl+shift+n=new_window"
        "ctrl+plus=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
        "ctrl+zero=reset_font_size"
      ];
    };
  };

  # Additional home packages
  home.packages = with pkgs; [
    # Development tools
    gh
    git-lfs
    pre-commit

    # Terminal utilities
    tldr
    navi

    # System info
    neofetch
    fastfetch

    # File operations
    duf
    dust
    ncdu

    # Network tools
    bandwhich
    trippy

    # JSON/Data tools
    fx
    gron

    # Process management
    procs
    bottom

    # Git tools
    delta
    difftastic

    # Note taking
    glow  # Markdown viewer

    # API testing
    httpie
    curlie
  ];

  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      # Essentials
      vim-sensible
      vim-surround
      vim-commentary
      vim-fugitive
      vim-gitgutter

      # File navigation
      telescope-nvim
      nvim-tree-lua

      # Syntax and language support
      nvim-treesitter.withAllGrammars
      nvim-lspconfig

      # Completion
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      cmp_luasnip

      # UI
      lualine-nvim
      bufferline-nvim
      nvim-web-devicons
      indent-blankline-nvim

      # Colorscheme
      catppuccin-nvim
      tokyonight-nvim

      # Utilities
      which-key-nvim
      gitsigns-nvim
      nvim-autopairs
      comment-nvim
    ];

    extraLuaConfig = ''
      -- Basic settings
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.smartindent = true
      vim.opt.wrap = false
      vim.opt.termguicolors = true
      vim.opt.signcolumn = "yes"
      vim.opt.updatetime = 250
      vim.opt.timeoutlen = 300
      vim.opt.clipboard = "unnamedplus"
      vim.opt.mouse = "a"
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.undofile = true

      -- Leader key
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      -- Colorscheme
      vim.cmd.colorscheme("catppuccin-mocha")

      -- Keymaps
      local keymap = vim.keymap.set

      -- Window navigation
      keymap("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
      keymap("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
      keymap("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
      keymap("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

      -- Buffer navigation
      keymap("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
      keymap("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })

      -- Clear search highlighting
      keymap("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search" })

      -- Save file
      keymap({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

      -- Telescope
      local telescope = require("telescope.builtin")
      keymap("n", "<leader>ff", telescope.find_files, { desc = "Find files" })
      keymap("n", "<leader>fg", telescope.live_grep, { desc = "Live grep" })
      keymap("n", "<leader>fb", telescope.buffers, { desc = "Buffers" })
      keymap("n", "<leader>fh", telescope.help_tags, { desc = "Help tags" })

      -- File tree
      keymap("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file tree" })

      -- Git
      keymap("n", "<leader>gs", telescope.git_status, { desc = "Git status" })
      keymap("n", "<leader>gc", telescope.git_commits, { desc = "Git commits" })

      -- Setup plugins
      require("nvim-tree").setup({})
      require("lualine").setup({
        options = {
          theme = "catppuccin",
        },
      })
      require("bufferline").setup({})
      require("gitsigns").setup({})
      require("nvim-autopairs").setup({})
      require("Comment").setup({})
      require("which-key").setup({})
      require("ibl").setup({})

      -- LSP setup
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- TypeScript/JavaScript
      lspconfig.ts_ls.setup({
        capabilities = capabilities,
      })

      -- Python
      lspconfig.pyright.setup({
        capabilities = capabilities,
      })

      -- Lua
      lspconfig.lua_ls.setup({
        capabilities = capabilities,
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
          },
        },
      })

      -- Completion setup
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    '';
  };

  # Starship prompt configuration
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
      git_branch = {
        symbol = " ";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      kubernetes = {
        disabled = false;
        symbol = "⎈ ";
      };
      nix_shell = {
        disabled = false;
        symbol = " ";
      };
    };
  };

  # GNOME settings
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Adwaita";
      font-name = "Cantarell 11";
      monospace-font-name = "JetBrainsMono Nerd Font 10";
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
      night-light-temperature = 3700;
    };

    "org/gnome/shell" = {
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
        "firefox.desktop"
        "org.gnome.TextEditor.desktop"
      ];
    };
  };

  # Allow home-manager to manage itself
  programs.home-manager.enable = true;
}
