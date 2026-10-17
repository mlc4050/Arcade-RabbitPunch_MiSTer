entity sprite_scan_line_tb is
end entity;

architecture test of sprite_scan_line_tb is
begin
    stored_rows : entity work.sprite_scan_tb
        generic map (
            GBOOL_DRAW => true,
            GBOOL_LINE => true
        );
end architecture;
