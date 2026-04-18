`timescale 1ns / 1ps

// cnn_mmio_interface
// ------------------
// A thin MMIO/BRAM wrapper around system_top.
//
// address[19] = 0 : memory space   (16-bit halfword BRAM)
// address[19] = 1 : config space   (16-bit registers)
//
// The wrapper keeps the existing accelerator datapath intact and only adds:
//   1) a stable memory image interface for model/image staging
//   2) a small register block for base/length programming
//   3) a sequencer that replays staged 32-bit words into system_top
//
// This keeps the current CNN_ACC architecture and borrows only the transaction
// pattern from the reference cnn_interface design.

module cnn_mmio_interface #(
  parameter integer MEM_AW       = 13,
  parameter integer MEM_HALFWORDS = (1 << MEM_AW)
) (
  input  wire        clk,
  input  wire        reset,
  input  wire [15:0] writedata,
  input  wire        write,
  input  wire        chipselect,
  input  wire [19:0] address,
  output reg  [15:0] readdata
);

  localparam [4:0] REG_CONTROL       = 5'd0;
  localparam [4:0] REG_STATUS        = 5'd1;
  localparam [4:0] REG_CONV_CFG_BASE = 5'd2;
  localparam [4:0] REG_CONV_CFG_LEN  = 5'd3;
  localparam [4:0] REG_CONV_WT_BASE  = 5'd4;
  localparam [4:0] REG_CONV_WT_LEN   = 5'd5;
  localparam [4:0] REG_FC_BIAS_BASE  = 5'd6;
  localparam [4:0] REG_FC_BIAS_LEN   = 5'd7;
  localparam [4:0] REG_FCW_BASE      = 5'd8;
  localparam [4:0] REG_FCW_LEN       = 5'd9;
  localparam [4:0] REG_IMAGE_BASE    = 5'd10;
  localparam [4:0] REG_IMAGE_LEN     = 5'd11;
  localparam [4:0] REG_PREDICT       = 5'd12;
  localparam [4:0] REG_IF_ERROR      = 5'd13;

  localparam [1:0] ENG_IDLE    = 2'd0;
  localparam [1:0] ENG_MODEL   = 2'd1;
  localparam [1:0] ENG_INFER   = 2'd2;

  localparam [3:0] ST_IDLE     = 4'd0;
  localparam [3:0] ST_RD_LO    = 4'd1;
  localparam [3:0] ST_WAIT_LO  = 4'd2;
  localparam [3:0] ST_CAP_LO   = 4'd3;
  localparam [3:0] ST_RD_HI    = 4'd4;
  localparam [3:0] ST_WAIT_HI  = 4'd5;
  localparam [3:0] ST_CAP_HI   = 4'd6;
  localparam [3:0] ST_SEND     = 4'd7;
  localparam [3:0] ST_GAP      = 4'd8;

  localparam [1:0] SEG_CONV_CFG = 2'd0;
  localparam [1:0] SEG_CONV_WT  = 2'd1;
  localparam [1:0] SEG_FC_BIAS  = 2'd2;
  localparam [1:0] SEG_FCW      = 2'd3;

  // ---------------------------------------------------------------------------
  // 16-bit staging BRAM
  // ---------------------------------------------------------------------------
  (* ramstyle = "M10K" *)
  reg [15:0] mem [0:MEM_HALFWORDS-1];

  reg [15:0]       mem_rdata_q;
  reg              host_mem_rd_q;
  reg [MEM_AW-1:0] mem_rd_addr_q;
  reg              mem_rd_pending_q;
  reg              mem_rd_host_q;

  wire mem_sel    = chipselect && !address[19];
  wire cfg_sel    = chipselect &&  address[19];
  wire mem_wr_req = mem_sel &&  write;
  wire mem_rd_req = mem_sel && !write;
  wire cfg_wr_req = cfg_sel &&  write;
  wire cfg_rd_req = cfg_sel && !write;
  wire mem_addr_ok = (address[18:0] < MEM_HALFWORDS);

  // ---------------------------------------------------------------------------
  // Config registers
  // ---------------------------------------------------------------------------
  reg [15:0] conv_cfg_base_hw;
  reg [15:0] conv_cfg_len_w;
  reg [15:0] conv_wt_base_hw;
  reg [15:0] conv_wt_len_w;
  reg [15:0] fc_bias_base_hw;
  reg [15:0] fc_bias_len_w;
  reg [15:0] fcw_base_hw;
  reg [15:0] fcw_len_w;
  reg [15:0] image_base_hw;
  reg [15:0] image_len_w;

  reg        model_loaded;
  reg        predict_done;
  reg [3:0]  predict_class_latched;
  reg [15:0] interface_error;
  reg [1:0]  eng_mode;
  wire       eng_busy = (eng_mode != ENG_IDLE);

  wire [15:0] cfg_status_word = {
    8'd0,
    predict_class_latched,
    predict_done,
    model_loaded,
    eng_busy,
    1'b0
  };

  reg [15:0] cfg_read_data;
  always @(*) begin
    cfg_read_data = 16'd0;
    case (address[4:0])
      REG_STATUS:        cfg_read_data = cfg_status_word;
      REG_CONV_CFG_BASE: cfg_read_data = conv_cfg_base_hw;
      REG_CONV_CFG_LEN:  cfg_read_data = conv_cfg_len_w;
      REG_CONV_WT_BASE:  cfg_read_data = conv_wt_base_hw;
      REG_CONV_WT_LEN:   cfg_read_data = conv_wt_len_w;
      REG_FC_BIAS_BASE:  cfg_read_data = fc_bias_base_hw;
      REG_FC_BIAS_LEN:   cfg_read_data = fc_bias_len_w;
      REG_FCW_BASE:      cfg_read_data = fcw_base_hw;
      REG_FCW_LEN:       cfg_read_data = fcw_len_w;
      REG_IMAGE_BASE:    cfg_read_data = image_base_hw;
      REG_IMAGE_LEN:     cfg_read_data = image_len_w;
      REG_PREDICT:       cfg_read_data = {12'd0, predict_class_latched};
      REG_IF_ERROR:      cfg_read_data = interface_error;
      default:           cfg_read_data = 16'd0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // system_top host-stream interface
  // ---------------------------------------------------------------------------
  reg         accel_load_sel;
  reg         accel_load_valid;
  reg  [31:0] accel_load_data;
  reg         accel_load_last;
  wire        accel_load_ready;
  wire        accel_busy;
  wire        accel_predict_valid;
  wire [3:0]  accel_predict_class;

  system_top u_system_top (
    .clk(clk),
    .rst_n(~reset),
    .load_sel(accel_load_sel),
    .load_valid(accel_load_valid),
    .load_data(accel_load_data),
    .load_last(accel_load_last),
    .load_ready(accel_load_ready),
    .busy(accel_busy),
    .predict_valid(accel_predict_valid),
    .predict_class(accel_predict_class)
  );

  // ---------------------------------------------------------------------------
  // Replay engine
  // ---------------------------------------------------------------------------
  reg [3:0] eng_state;
  reg [1:0] model_seg_idx;
  reg [15:0] seg_word_idx;
  reg [15:0] seg_word_count;
  reg [15:0] lo_halfword;
  reg [15:0] hi_halfword;

  function [15:0] model_seg_base;
    input [1:0] seg;
    begin
      case (seg)
        SEG_CONV_CFG: model_seg_base = conv_cfg_base_hw;
        SEG_CONV_WT:  model_seg_base = conv_wt_base_hw;
        SEG_FC_BIAS:  model_seg_base = fc_bias_base_hw;
        default:      model_seg_base = fcw_base_hw;
      endcase
    end
  endfunction

  function [15:0] model_seg_len;
    input [1:0] seg;
    begin
      case (seg)
        SEG_CONV_CFG: model_seg_len = conv_cfg_len_w;
        SEG_CONV_WT:  model_seg_len = conv_wt_len_w;
        SEG_FC_BIAS:  model_seg_len = fc_bias_len_w;
        default:      model_seg_len = fcw_len_w;
      endcase
    end
  endfunction

  // Memory read arbitration: the engine owns BRAM while active.
  wire issue_eng_read = (eng_state == ST_RD_LO) || (eng_state == ST_RD_HI);
  wire [15:0] current_seg_base = (eng_mode == ENG_INFER) ? image_base_hw
                                                         : model_seg_base(model_seg_idx);
  wire [15:0] current_seg_len  = (eng_mode == ENG_INFER) ? image_len_w
                                                         : model_seg_len(model_seg_idx);
  wire [15:0] current_halfword_addr = current_seg_base + {seg_word_idx, 1'b0} +
                                      ((eng_state == ST_RD_HI) ? 16'd1 : 16'd0);
  wire eng_read_in_range = (current_halfword_addr < MEM_HALFWORDS);

  always @(posedge clk) begin
    if (reset) begin
      mem_rdata_q      <= 16'd0;
      host_mem_rd_q    <= 1'b0;
      mem_rd_addr_q    <= {MEM_AW{1'b0}};
      mem_rd_pending_q <= 1'b0;
      mem_rd_host_q    <= 1'b0;
    end else begin
      host_mem_rd_q <= 1'b0;

      if (mem_wr_req && !eng_busy && mem_addr_ok)
        mem[address[MEM_AW-1:0]] <= writedata;

      if (mem_rd_pending_q) begin
        mem_rdata_q   <= mem[mem_rd_addr_q];
        host_mem_rd_q <= mem_rd_host_q;
      end

      mem_rd_pending_q <= 1'b0;

      if (issue_eng_read && eng_read_in_range) begin
        mem_rd_addr_q    <= current_halfword_addr[MEM_AW-1:0];
        mem_rd_pending_q <= 1'b1;
        mem_rd_host_q    <= 1'b0;
      end else if (mem_rd_req && !eng_busy && mem_addr_ok) begin
        mem_rd_addr_q    <= address[MEM_AW-1:0];
        mem_rd_pending_q <= 1'b1;
        mem_rd_host_q    <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Register block, status latches, and replay FSM
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (reset) begin
      conv_cfg_base_hw      <= 16'd0;
      conv_cfg_len_w        <= 16'd45;
      conv_wt_base_hw       <= 16'd90;
      conv_wt_len_w         <= 16'd225;
      fc_bias_base_hw       <= 16'd540;
      fc_bias_len_w         <= 16'd10;
      fcw_base_hw           <= 16'd560;
      fcw_len_w             <= 16'd864;
      image_base_hw         <= 16'd2288;
      image_len_w           <= 16'd1024;
      model_loaded          <= 1'b0;
      predict_done          <= 1'b0;
      predict_class_latched <= 4'd0;
      interface_error       <= 16'd0;
      eng_mode              <= ENG_IDLE;
      eng_state             <= ST_IDLE;
      model_seg_idx         <= SEG_CONV_CFG;
      seg_word_idx          <= 16'd0;
      seg_word_count        <= 16'd0;
      lo_halfword           <= 16'd0;
      hi_halfword           <= 16'd0;
    end else begin
      if (accel_predict_valid) begin
        predict_done          <= 1'b1;
        predict_class_latched <= accel_predict_class;
      end

      if (cfg_wr_req) begin
        case (address[4:0])
          REG_CONTROL: begin
            if (writedata[2]) begin
              predict_done    <= 1'b0;
              interface_error <= 16'd0;
            end

            if (writedata[0]) begin
              if (eng_busy || accel_busy) begin
                interface_error[0] <= 1'b1;
              end else begin
                eng_mode       <= ENG_MODEL;
                eng_state      <= ST_RD_LO;
                model_seg_idx  <= SEG_CONV_CFG;
                seg_word_idx   <= 16'd0;
                seg_word_count <= conv_cfg_len_w;
                predict_done   <= 1'b0;
                model_loaded   <= 1'b0;
              end
            end

            if (writedata[1]) begin
              if (eng_busy || accel_busy) begin
                interface_error[1] <= 1'b1;
              end else if (!model_loaded) begin
                interface_error[2] <= 1'b1;
              end else begin
                eng_mode       <= ENG_INFER;
                eng_state      <= ST_RD_LO;
                seg_word_idx   <= 16'd0;
                seg_word_count <= image_len_w;
                predict_done   <= 1'b0;
              end
            end
          end

          REG_CONV_CFG_BASE: conv_cfg_base_hw <= writedata;
          REG_CONV_CFG_LEN:  conv_cfg_len_w   <= writedata;
          REG_CONV_WT_BASE:  conv_wt_base_hw  <= writedata;
          REG_CONV_WT_LEN:   conv_wt_len_w    <= writedata;
          REG_FC_BIAS_BASE:  fc_bias_base_hw  <= writedata;
          REG_FC_BIAS_LEN:   fc_bias_len_w    <= writedata;
          REG_FCW_BASE:      fcw_base_hw      <= writedata;
          REG_FCW_LEN:       fcw_len_w        <= writedata;
          REG_IMAGE_BASE:    image_base_hw    <= writedata;
          REG_IMAGE_LEN:     image_len_w      <= writedata;
          default: begin
          end
        endcase
      end

      case (eng_state)
        ST_IDLE: begin
        end

        ST_RD_LO: begin
          if (!eng_read_in_range) begin
            interface_error[3] <= 1'b1;
            eng_mode           <= ENG_IDLE;
            eng_state          <= ST_IDLE;
          end else begin
            eng_state <= ST_WAIT_LO;
          end
        end

        ST_WAIT_LO: begin
          eng_state <= ST_CAP_LO;
        end

        ST_CAP_LO: begin
          lo_halfword <= mem_rdata_q;
          eng_state   <= ST_RD_HI;
        end

        ST_RD_HI: begin
          if (!eng_read_in_range) begin
            interface_error[4] <= 1'b1;
            eng_mode           <= ENG_IDLE;
            eng_state          <= ST_IDLE;
          end else begin
            eng_state <= ST_WAIT_HI;
          end
        end

        ST_WAIT_HI: begin
          eng_state <= ST_CAP_HI;
        end

        ST_CAP_HI: begin
          hi_halfword <= mem_rdata_q;
          eng_state   <= ST_SEND;
        end

        ST_SEND: begin
          if (accel_load_ready) begin
            if (seg_word_idx == (seg_word_count - 16'd1)) begin
              if (eng_mode == ENG_MODEL) begin
                if (model_seg_idx == SEG_FCW) begin
                  model_loaded <= 1'b1;
                  eng_mode     <= ENG_IDLE;
                  eng_state    <= ST_IDLE;
                end else begin
                  model_seg_idx <= model_seg_idx + 2'd1;
                  seg_word_idx  <= 16'd0;
                  eng_state     <= ST_GAP;
                end
              end else begin
                eng_mode    <= ENG_IDLE;
                eng_state   <= ST_IDLE;
                seg_word_idx <= 16'd0;
              end
            end else begin
              seg_word_idx <= seg_word_idx + 16'd1;
              eng_state    <= ST_RD_LO;
            end
          end
        end

        ST_GAP: begin
          seg_word_count <= model_seg_len(model_seg_idx);
          eng_state      <= ST_RD_LO;
        end

        default: begin
          eng_state <= ST_IDLE;
          eng_mode  <= ENG_IDLE;
        end
      endcase
    end
  end

  always @(*) begin
    accel_load_valid = (eng_state == ST_SEND);
    accel_load_data  = {hi_halfword, lo_halfword};
    accel_load_sel   = (eng_mode == ENG_INFER);
    accel_load_last  = (eng_state == ST_SEND) && (seg_word_idx == (seg_word_count - 16'd1));
  end

  // ---------------------------------------------------------------------------
  // Read response
  // ---------------------------------------------------------------------------
  always @(*) begin
    readdata = 16'd0;
    if (host_mem_rd_q)
      readdata = mem_rdata_q;
    else if (cfg_rd_req)
      readdata = cfg_read_data;
  end

endmodule
