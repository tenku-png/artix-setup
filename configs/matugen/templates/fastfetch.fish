# fastfetch with matugen colors (generated, see ~/.config/matugen/templates)
function fastfetch --wraps fastfetch
    command fastfetch --color-keys '{{colors.primary.default.hex}}' --color-title '{{colors.tertiary.default.hex}}' $argv
end
