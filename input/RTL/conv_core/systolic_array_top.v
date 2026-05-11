// ============================================================
// 16x4 Systolic Array 顶层
// - 保持当前工程使用的 flat 输入 / flat 输出 / 列流接口
// - 内部计算逻辑替换为 mode_cfg + runtime cur_k 版本
// - 当前 Conv1_top 先固定驱动 mode_cfg=2'b00，以保证现有 L1 TB 兼容
// ============================================================

module systolic_array_top #(
  parameter integer DATA_W = 8,
  parameter integer ROWS   = 16,
  parameter integer COLS   = 4,
  parameter integer DOT_K  = 9,   // legacy compatibility only
  parameter integer ACC_W  = 23
)(
  input  wire clk,
  input  wire rst_n,
  input  wire start_pulse,
  input  wire [1:0] mode_cfg,
  input  wire [4:0] valid_rows_cfg,

  // 扁平输入：
  // a_in_flat[(r+1)*DATA_W-1 : r*DATA_W] 对应第 r 行左边界输入
  input  wire signed [ROWS*DATA_W-1:0] a_in_flat,
  // b_in_flat[(c+1)*DATA_W-1 : c*DATA_W] 对应第 c 列上边界输入
  input  wire signed [COLS*DATA_W-1:0] b_in_flat,

  // 扁平输出：
  // idx = r*COLS + c
  // c_out_flat[(idx+1)*ACC_W-1 : idx*ACC_W] 对应 c_out[r][c]
  output wire signed [ROWS*COLS*ACC_W-1:0] c_out_flat,
  output wire done,

  // 每列实时串流输出（保持当前 Conv1_top 输出协议）
  output reg  signed [COLS*ACC_W-1:0] col_stream_data_flat,
  output reg         [COLS-1:0]       col_stream_valid,
  output reg         [COLS-1:0]       col_stream_last
);

  localparam [1:0] MODE_CONV1 = 2'b00;
  localparam [1:0] MODE_CONV2 = 2'b01;
  localparam [1:0] MODE_CONV3 = 2'b10;
  localparam [1:0] MODE_FC    = 2'b11;
  localparam integer MAX_DOT_K    = 288;
  localparam integer CNT_W        = $clog2(MAX_DOT_K + 1);
  localparam integer START_STAGES = ROWS + COLS - 1;

  integer k;
  integer sc;
  integer data_lo;

  reg  [START_STAGES-1:0] start_pipe;
  reg  [CNT_W-1:0]        cur_k;
  wire                    fc_mode;

  reg  [COLS-1:0] stream_active;
  reg  [COLS-1:0] stream_arm;
  reg  [7:0]      stream_row [0:COLS-1];
  reg  [4:0]      stream_rows_limit [0:COLS-1];
  reg  [4:0]      arm_rows_limit [0:COLS-1];
  reg  [4:0]      col_rows_cfg [0:COLS-1];
  reg  [4:0]      valid_rows_pipe [0:COLS-1];
  reg             valid_rows_pipe_v [0:COLS-1];

  wire signed [DATA_W-1:0] a_in [0:ROWS-1];
  wire signed [DATA_W-1:0] b_in [0:COLS-1];
  wire                    start_ij [0:ROWS-1][0:COLS-1];
  wire                    finish_ij [0:ROWS-1][0:COLS-1];

  wire signed [DATA_W-1:0] pe_left   [0:ROWS-1][0:COLS-1];
  wire signed [DATA_W-1:0] pe_up     [0:ROWS-1][0:COLS-1];
  wire signed [DATA_W-1:0] pe_right  [0:ROWS-1][0:COLS-1];
  wire signed [DATA_W-1:0] pe_bottom [0:ROWS-1][0:COLS-1];
  wire signed [ACC_W-1:0]  pe_result [0:ROWS-1][0:COLS-1];
  reg                      conv_done_r;

  assign fc_mode = (mode_cfg == MODE_FC);

  always @(*) begin
    case (mode_cfg)
      MODE_CONV1: cur_k = 9;
      MODE_CONV2: cur_k = 36;
      MODE_CONV3: cur_k = 72;
      default:    cur_k = 288;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_pipe <= {START_STAGES{1'b0}};
    end else begin
      start_pipe[0] <= start_pulse;
      for (k=1; k<START_STAGES; k=k+1) begin
        start_pipe[k] <= start_pipe[k-1];
      end
    end
  end

  // FC mode 只使用第一行前三个 PE；conv 模式按当前 block 的真实 valid_rows 收尾。
  always @* begin
    case (valid_rows_cfg)
      5'd0:    conv_done_r = 1'b0;
      5'd1:    conv_done_r = finish_ij[0][COLS-1];
      5'd2:    conv_done_r = finish_ij[1][COLS-1];
      5'd3:    conv_done_r = finish_ij[2][COLS-1];
      5'd4:    conv_done_r = finish_ij[3][COLS-1];
      5'd5:    conv_done_r = finish_ij[4][COLS-1];
      5'd6:    conv_done_r = finish_ij[5][COLS-1];
      5'd7:    conv_done_r = finish_ij[6][COLS-1];
      5'd8:    conv_done_r = finish_ij[7][COLS-1];
      5'd9:    conv_done_r = finish_ij[8][COLS-1];
      5'd10:   conv_done_r = finish_ij[9][COLS-1];
      5'd11:   conv_done_r = finish_ij[10][COLS-1];
      5'd12:   conv_done_r = finish_ij[11][COLS-1];
      5'd13:   conv_done_r = finish_ij[12][COLS-1];
      5'd14:   conv_done_r = finish_ij[13][COLS-1];
      5'd15:   conv_done_r = finish_ij[14][COLS-1];
      default: conv_done_r = finish_ij[15][COLS-1];
    endcase
  end
  assign done = fc_mode ? finish_ij[0][2] : conv_done_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      col_stream_data_flat <= {(COLS*ACC_W){1'b0}};
      col_stream_valid     <= {COLS{1'b0}};
      col_stream_last      <= {COLS{1'b0}};
      stream_active        <= {COLS{1'b0}};
      stream_arm           <= {COLS{1'b0}};
      for (sc=0; sc<COLS; sc=sc+1) begin
        stream_row[sc] <= 8'd0;
        stream_rows_limit[sc] <= 5'd0;
        arm_rows_limit[sc]    <= 5'd0;
        col_rows_cfg[sc]      <= 5'd0;
        valid_rows_pipe[sc]   <= 5'd0;
        valid_rows_pipe_v[sc] <= 1'b0;
      end
    end else begin
      col_stream_valid <= {COLS{1'b0}};
      col_stream_last  <= {COLS{1'b0}};
      for (sc=0; sc<COLS; sc=sc+1) begin
        data_lo = sc*ACC_W;
        col_stream_data_flat[data_lo +: ACC_W] <= {ACC_W{1'b0}};
      end

      valid_rows_pipe[0]   <= valid_rows_cfg;
      valid_rows_pipe_v[0] <= start_pulse;
      for (sc=1; sc<COLS; sc=sc+1) begin
        valid_rows_pipe[sc]   <= valid_rows_pipe[sc-1];
        valid_rows_pipe_v[sc] <= valid_rows_pipe_v[sc-1];
      end

      if (start_pulse)
        col_rows_cfg[0] <= valid_rows_cfg;
      for (sc=1; sc<COLS; sc=sc+1) begin
        if (valid_rows_pipe_v[sc-1])
          col_rows_cfg[sc] <= valid_rows_pipe[sc-1];
      end

      for (sc=0; sc<COLS; sc=sc+1) begin
        if (!stream_arm[sc] && finish_ij[0][sc]) begin
          stream_arm[sc] <= 1'b1;
          arm_rows_limit[sc] <= col_rows_cfg[sc];
        end

        data_lo = sc*ACC_W;
        if (!stream_active[sc] && stream_arm[sc]) begin
          stream_arm[sc] <= 1'b0;
          stream_rows_limit[sc] <= arm_rows_limit[sc];
          if (arm_rows_limit[sc] != 5'd0) begin
            col_stream_valid[sc] <= 1'b1;
            col_stream_last[sc]  <= (arm_rows_limit[sc] == 5'd1);
            col_stream_data_flat[data_lo +: ACC_W] <= pe_result[0][sc];
          end

          if (arm_rows_limit[sc] <= 5'd1) begin
            stream_active[sc] <= 1'b0;
            stream_row[sc]    <= 8'd0;
          end else begin
            stream_active[sc] <= 1'b1;
            stream_row[sc]    <= 8'd1;
          end
        end else if (stream_active[sc]) begin
          col_stream_valid[sc] <= (stream_row[sc] < stream_rows_limit[sc]);
          if (stream_row[sc] < stream_rows_limit[sc])
            col_stream_data_flat[data_lo +: ACC_W] <= pe_result[stream_row[sc]][sc];

          if (stream_row[sc] == (stream_rows_limit[sc]-1'b1)) begin
            col_stream_last[sc] <= 1'b1;
            stream_active[sc]   <= 1'b0;
            stream_row[sc]      <= 8'd0;
          end else begin
            stream_row[sc]      <= stream_row[sc] + 8'd1;
          end
        end
      end
    end
  end

  genvar ar, bc;
  generate
    for (ar=0; ar<ROWS; ar=ar+1) begin: GEN_A_IN
      localparam integer A_LO = ar*DATA_W;
      localparam integer A_HI = ar*DATA_W + (DATA_W-1);
      assign a_in[ar] = a_in_flat[A_HI:A_LO];
    end
    for (bc=0; bc<COLS; bc=bc+1) begin: GEN_B_IN
      localparam integer B_LO = bc*DATA_W;
      localparam integer B_HI = bc*DATA_W + (DATA_W-1);
      assign b_in[bc] = b_in_flat[B_HI:B_LO];
    end
  endgenerate

  genvar r, c;
  generate
    for (r=0; r<ROWS; r=r+1) begin: GEN_ROW
      for (c=0; c<COLS; c=c+1) begin: GEN_COL
        localparam integer O_LO = (r*COLS + c)*ACC_W;
        localparam integer O_HI = (r*COLS + c)*ACC_W + (ACC_W-1);

        if (c == 0) begin: LEFT_EDGE
          assign pe_left[r][c] = a_in[r];
        end else begin: LEFT_INNER
          assign pe_left[r][c] = pe_right[r][c-1];
        end

        if (r == 0) begin: UP_EDGE
          assign pe_up[r][c] = b_in[c];
        end else begin: UP_INNER
          assign pe_up[r][c] = pe_bottom[r-1][c];
        end

        assign start_ij[r][c] = fc_mode ?
                                (((r == 0) && (c < 3)) ? ((c == 0) ? start_pulse : start_pipe[c-1]) : 1'b0) :
                                (((r == 0) && (c == 0)) ? start_pulse : start_pipe[r+c-1]);

        single_PE #(
          .DATA_W(DATA_W),
          .CNT_W (CNT_W),
          .ACC_W (ACC_W)
        ) PE_ij (
          .clk   (clk),
          .rst_n (rst_n),
          .start (start_ij[r][c]),
          .cur_k (cur_k),
          .finish(finish_ij[r][c]),
          .left  (pe_left[r][c]),
          .up    (pe_up[r][c]),
          .right (pe_right[r][c]),
          .bottom(pe_bottom[r][c]),
          .result(pe_result[r][c])
        );

        assign c_out_flat[O_HI:O_LO] = pe_result[r][c];
      end
    end
  endgenerate

endmodule


module single_PE #(
  parameter integer DATA_W = 8,
  parameter integer CNT_W  = 9,
  parameter integer ACC_W  = 23
)(
  input  wire clk,
  input  wire rst_n,
  input  wire start,
  input  wire [CNT_W-1:0] cur_k,
  output reg  finish,
  input  wire signed [DATA_W-1:0] left,
  input  wire signed [DATA_W-1:0] up,

  output reg  signed [DATA_W-1:0] right,
  output reg  signed [DATA_W-1:0] bottom,
  output reg  signed [ACC_W-1:0] result
);

  reg  signed [ACC_W-1:0]    mem;
  wire signed [2*DATA_W-1:0] product;
  reg  [CNT_W-1:0]           cnt;

  assign product = left * up;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      right  <= {DATA_W{1'b0}};
      bottom <= {DATA_W{1'b0}};
      mem    <= {ACC_W{1'b0}};
      result <= {ACC_W{1'b0}};
      finish <= 1'b0;
      cnt    <= {CNT_W{1'b0}};
    end else begin
      right  <= left;
      bottom <= up;
      finish <= 1'b0;

      if (start) begin
        if (cur_k <= 1) begin
          result <= {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};
          mem    <= {ACC_W{1'b0}};
          cnt    <= {CNT_W{1'b0}};
          finish <= 1'b1;
        end else begin
          mem <= {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};
          cnt <= {{(CNT_W-1){1'b0}}, 1'b1};
        end
      end else if (cnt != {CNT_W{1'b0}}) begin
        if (cnt == cur_k - 1'b1) begin
          result <= mem + {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};
          mem    <= {ACC_W{1'b0}};
          cnt    <= {CNT_W{1'b0}};
          finish <= 1'b1;
        end else begin
          mem <= mem + {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};
          cnt <= cnt + 1'b1;
        end
      end
    end
  end

endmodule
