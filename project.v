/*
 * Blooming flower - VGA 640x480 @ 60 Hz, 2 bits per colour channel
 * Timeline (60 frames = 1 s, loops every ~17 s):
 *   0-4 s    stem grows, bud rises
 *   2.7-6.9s petals open (green bud turns pink)
 *   then hold, fade to black, repeat
 */
`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ---------------- VGA plumbing ----------------
  wire       hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  reg  [1:0] R, G, B;

  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;
  wire _unused_ok = &{ena, ui_in, uio_in};

  hvsync_generator hvsync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // ---------------- Frame counter (1 tick per frame) ----------------
  reg [9:0] t;
  reg       vs_prev;
  always @(posedge clk) begin
    if (~rst_n) begin
      t       <= 10'd0;
      vs_prev <= 1'b0;
    end else begin
      vs_prev <= vsync;
      if (vsync & ~vs_prev) t <= t + 10'd1;
    end
  end

  // ---------------- Animation parameters ----------------
  wire [7:0]  grow    = (t < 10'd256) ? t[7:0] : 8'hFF;

  wire [9:0]  tb      = t - 10'd160;
  wire [7:0]  o_lin   = (t < 10'd160) ? 8'd0 : (t < 10'd416) ? tb[7:0] : 8'hFF;
  wire [7:0]  o_inv   = 8'hFF - o_lin;
  wire [15:0] o_sq    = o_inv * o_inv;
  wire [7:0]  bloom   = 8'hFF - o_sq[15:8];          // ease-out 0..255

  wire [15:0] grow_h  = grow * 8'd240;
  wire [9:0]  hy      = 10'd440 - {2'b00, grow_h[15:8]};   // flower head centre y

  wire [15:0] bloom_s = bloom * 8'd66;
  wire [11:0] A       = 12'd6 + {9'd0, grow[7:5]} + {4'd0, bloom_s[15:8]}; // petal size
  wire [11:0] A2      = (A >> 1) + (A >> 2);                                // 0.75 * A

  // ---------------- Geometry ----------------
  wire [11:0] px   = {2'b00, pix_x};
  wire [11:0] py   = {2'b00, pix_y};
  wire [11:0] hy12 = {2'b00, hy};

  wire [11:0] ax = (px >= 12'd320) ? px - 12'd320 : 12'd320 - px;
  wire [11:0] ay = (py >= hy12)    ? py - hy12    : hy12 - py;

  // Axis petals (up/down/left/right): fold into one octant
  wire [11:0] m  = (ax > ay) ? ax : ay;
  wire [11:0] n  = (ax > ay) ? ay : ax;
  wire [11:0] dm = (m > A) ? m - A : A - m;
  wire [23:0] e_axis = dm * dm + n * n * 5;
  wire [23:0] a_sq   = A * A;
  wire        axis_hit = (e_axis < a_sq);

  // Diagonal petals
  wire [12:0] ssum = {1'b0, ax} + {1'b0, ay};
  wire [12:0] p    = (ssum >> 1) + (ssum >> 2);
  wire [11:0] qd   = (ax > ay) ? ax - ay : ay - ax;
  wire [11:0] q    = (qd >> 1) + (qd >> 2);
  wire [12:0] A2x  = {1'b0, A2};
  wire [12:0] dp   = (p > A2x) ? p - A2x : A2x - p;
  wire [23:0] e_diag = dp * dp + q * q * 5;
  wire [23:0] a2_sq  = A2 * A2;
  wire        diag_hit = (e_diag < a2_sq);

  // Flower centre
  wire [11:0] rc  = 12'd5 + {9'd0, bloom[7:5]};
  wire [23:0] d2  = ax * ax + ay * ay;
  wire [23:0] rc2 = rc * rc;
  wire        center_hit = (d2 < rc2);

  // Stem
  wire stem_hit = (ax <= 12'd2) && (py >= hy12) && (py < 12'd445);

  // Leaves (left one higher, right one lower)
  wire        leaf_on = (grow >= 8'd200);
  wire [11:0] leafy   = (px < 12'd320) ? 12'd360 : 12'd400;
  wire [11:0] lx      = (ax >= 12'd45) ? ax - 12'd45 : 12'd45 - ax;
  wire [11:0] ly      = (py >= leafy) ? py - leafy : leafy - py;
  wire [31:0] e_leaf  = lx * lx * 9 + ly * ly * 100;
  wire        leaf_hit = leaf_on && (e_leaf < 32'd14400);

  // Stars
  wire [15:0] hsh      = (pix_x * 16'd2477) ^ (pix_y * 16'd9871);
  wire        star_hit = (hsh[11:0] == 12'hA5C) && (pix_y < 10'd200);

  wire dth = pix_x[0] ^ pix_y[0];   // checker dither

  // ---------------- Colour ----------------
  reg [1:0] pr, pg, pb;
  wire      is_bud = (bloom < 8'd60);

  always @* begin
    // Dusk sky gradient with dithered band edges
    case (pix_y[8:5])
      4'd0, 4'd1, 4'd2: begin pr = 2'd0; pg = 2'd0; pb = 2'd1; end
      4'd3:             begin pr = 2'd0; pg = 2'd0; pb = dth ? 2'd2 : 2'd1; end
      4'd4, 4'd5:       begin pr = 2'd0; pg = 2'd0; pb = 2'd2; end
      4'd6:             begin pr = dth ? 2'd1 : 2'd0; pg = 2'd0; pb = 2'd2; end
      4'd7, 4'd8:       begin pr = 2'd1; pg = 2'd0; pb = 2'd2; end
      4'd9:             begin pr = dth ? 2'd2 : 2'd1; pg = 2'd0; pb = 2'd2; end
      default:          begin pr = 2'd2; pg = 2'd0; pb = 2'd2; end
    endcase

    if (star_hit) begin
      if (t[4]) begin pr = 2'd3; pg = 2'd3; pb = 2'd3; end
      else      begin pr = 2'd2; pg = 2'd2; pb = 2'd3; end
    end

    if (stem_hit) begin
      pr = 2'd0; pg = (ax == 12'd0) ? 2'd3 : 2'd2; pb = 2'd0;
    end

    if (leaf_hit) begin
      if (ly < 12'd2) begin pr = 2'd1; pg = 2'd3; pb = 2'd1; end
      else            begin pr = 2'd0; pg = 2'd2; pb = 2'd0; end
    end

    // Diagonal petals (back layer)
    if (diag_hit) begin
      if (is_bud) begin pr = 2'd0; pg = 2'd2; pb = 2'd0; end
      else if (p < A2x) begin pr = 2'd2; pg = 2'd0; pb = 2'd2; end
      else              begin pr = 2'd3; pg = 2'd2; pb = 2'd3; end
    end

    // Axis petals (front layer)
    if (axis_hit) begin
      if (is_bud) begin
        pr = 2'd0; pg = (m < A) ? 2'd2 : 2'd3; pb = 2'd0;
      end else if (n < 12'd2) begin            // centre vein
        pr = 2'd3; pg = 2'd2; pb = 2'd2;
      end else if (m < A) begin                // inner half
        pr = 2'd3; pg = 2'd0; pb = 2'd1;
      end else begin                           // outer half
        pr = 2'd3; pg = 2'd1; pb = 2'd2;
      end
    end

    // Centre with seed dither
    if (center_hit && bloom > 8'd20) begin
      pr = 2'd3; pg = dth ? 2'd3 : 2'd2; pb = 2'd0;
    end

    // Ground (drawn last so it hides the stem base)
    if (py >= 12'd440) begin
      if (py < 12'd444) begin pr = 2'd0; pg = 2'd2; pb = 2'd0; end
      else begin
        pr = 2'd0; pg = dth ? 2'd1 : 2'd0; pb = 2'd0;
      end
    end
  end

  // ---------------- Fade in/out + blanking ----------------
  wire [1:0] dim = (t < 10'd24 || t >= 10'd1000) ? 2'd2 :
                   (t < 10'd48 || t >= 10'd976)  ? 2'd1 : 2'd0;

  always @* begin
    if (!video_active || dim == 2'd2) begin
      R = 2'd0; G = 2'd0; B = 2'd0;
    end else if (dim == 2'd1) begin
      R = {1'b0, pr[1]}; G = {1'b0, pg[1]}; B = {1'b0, pb[1]};
    end else begin
      R = pr; G = pg; B = pb;
    end
  end

endmodule
