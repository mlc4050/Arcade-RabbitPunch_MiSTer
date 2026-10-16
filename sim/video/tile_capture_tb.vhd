entity tile_capture_tb is
end entity;

architecture test of tile_capture_tb is
begin
    captured_layers : entity work.tile_layer_tb
        generic map (G_CAPTURE => true);
end architecture;
