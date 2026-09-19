`default_nettype none

module hvsync_generator (
    input  wire       clk,
    input  wire       reset,
    output reg        hsync,
    output reg        vsync,
    output wire       display_on,
    output reg  [9:0] hpos,
    output reg  [9:0] vpos
);
  // 640x480 @ 60 Hz (25.175 MHz pixel clock)
  localparam H_DISPLAY = 640;
  localparam H_FRONT   = 16;
  localparam H_SYNC    = 96;
  localparam H_BACK    = 48;

  localparam V_DISPLAY = 480;
  localparam V_BOTTOM  = 10;
  localparam V_SYNC    = 2;
  localparam V_TOP     = 33;

  localparam H_SYNC_START = H_DISPLAY + H_FRONT;
  localparam H_SYNC_END   = H_DISPLAY + H_FRONT + H_SYNC - 1;
  localparam H_MAX        = H_DISPLAY + H_FRONT + H_SYNC + H_BACK - 1;

  localparam V_SYNC_START = V_DISPLAY + V_BOTTOM;
  localparam V_SYNC_END   = V_DISPLAY + V_BOTTOM + V_SYNC - 1;
  localparam V_MAX        = V_DISPLAY + V_BOTTOM + V_SYNC + V_TOP - 1;

  wire hmaxxed = (hpos == H_MAX) || reset;
  wire vmaxxed = (vpos == V_MAX) || reset;

  // Horizontal counter + hsync (active low)
  always @(posedge clk) begin
    hsync <= ~(hpos >= H_SYNC_START && hpos <= H_SYNC_END);
    if (hmaxxed) hpos <= 0;
    else         hpos <= hpos + 1;
  end

  // Vertical counter + vsync (active low)
  always @(posedge clk) begin
    vsync <= ~(vpos >= V_SYNC_START && vpos <= V_SYNC_END);
    if (hmaxxed) begin
      if (vmaxxed) vpos <= 0;
      else         vpos <= vpos + 1;
    end
  end

  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

endmodule