entity sprite_scan_line_tb is
end entity;

architecture test of sprite_scan_line_tb is
begin
    stored_rows : entity work.sprite_scan_tb
        generic map (
            G_DRAW => true,
            G_LINE => true
        );
end architecture;
