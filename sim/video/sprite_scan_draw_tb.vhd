entity sprite_scan_draw_tb is
end entity;

architecture test of sprite_scan_draw_tb is
begin
    selected_rows : entity work.sprite_scan_tb
        generic map (GBOOL_DRAW => true);
end architecture;
