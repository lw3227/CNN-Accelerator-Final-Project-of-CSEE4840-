`timescale 1ns / 1ps

// cnn_mmio_interface
// ------------------
// A thin MMIO/BRAM wrapper around system_top.
//
// address[12] = 0 : memory space   (16 KiB 32-bit word BRAM)
// address[12] = 1 : config space   (32-bit MMIO registers, low 16 bits keep
//                                   the original control/status ABI)
//
// The wrapper keeps the existing accelerator datapath intact and only adds:
//   1) a stable memory image interface for model/image staging
//   2) a small register block for base/length programming
//   3) a sequencer that replays staged 32-bit words into system_top
//
// This keeps the current CNN_ACC architecture and borrows only the transaction
// pattern from the reference cnn_interface design.
//
// Notes on the slightly "mixed-width" looking register map:
//   - Control/status bits stay in the low 16 bits so the existing HPS helpers
//     and docs keep working after the move to a 32-bit Avalon-MM slave.
//   - Profile counters are already 32-bit values, so the legacy *_HI slots are
//     treated as the canonical full-width readback locations. The matching
//     *_LO slots are kept as zero/reserved padding for compatibility.

module cnn_mmio_interface #(
  parameter integer MEM_AW       = 12,
  parameter integer MEM_WORDS    = (1 << MEM_AW)
) (
  input  wire        clk,
  input  wire        reset,
  input  wire [31:0] writedata,
  input  wire [3:0]  byteenable,
  input  wire        write,
  input  wire        read,
  input  wire        chipselect,
  input  wire [MEM_AW:0] address,
  output reg  [31:0] readdata,
  output wire        debug_model_loaded,
  output wire        debug_predict_done,
  output wire [3:0]  debug_predict_class,
  output wire [15:0] debug_interface_error
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
  localparam [4:0] REG_PROFILE_L1_LO     = 5'd14;
  localparam [4:0] REG_PROFILE_L1_HI     = 5'd15;
  localparam [4:0] REG_PROFILE_L2_P0_LO  = 5'd16;
  localparam [4:0] REG_PROFILE_L2_P0_HI  = 5'd17;
  localparam [4:0] REG_PROFILE_L2_P1_LO  = 5'd18;
  localparam [4:0] REG_PROFILE_L2_P1_HI  = 5'd19;
  localparam [4:0] REG_PROFILE_L3_P0_LO  = 5'd20;
  localparam [4:0] REG_PROFILE_L3_P0_HI  = 5'd21;
  localparam [4:0] REG_PROFILE_L3_P1_LO  = 5'd22;
  localparam [4:0] REG_PROFILE_L3_P1_HI  = 5'd23;
  localparam [4:0] REG_PROFILE_FC_LO     = 5'd24;
  localparam [4:0] REG_PROFILE_FC_HI     = 5'd25;
  localparam [4:0] REG_PROFILE_ARGMAX_LO = 5'd26;
  localparam [4:0] REG_PROFILE_ARGMAX_HI = 5'd27;
  localparam [4:0] REG_PROFILE_TOTAL_LO  = 5'd28;
  localparam [4:0] REG_PROFILE_TOTAL_HI  = 5'd29;
  localparam [4:0] REG_LAST_WRITE        = 5'd30;
  localparam [4:0] REG_MAGIC             = 5'd31;

  localparam [31:0] CFG_MAGIC_WORD = 32'h434E4E32; // "CNN2"

  localparam [1:0] ENG_IDLE    = 2'd0;
  localparam [1:0] ENG_MODEL   = 2'd1;
  localparam [1:0] ENG_INFER   = 2'd2;

  localparam [2:0] ST_IDLE     = 3'd0;
  localparam [2:0] ST_RD       = 3'd1;
  localparam [2:0] ST_WAIT_RD  = 3'd2;
  localparam [2:0] ST_SEND     = 3'd3;
  localparam [2:0] ST_GAP      = 3'd4;

  localparam [1:0] SEG_CONV_CFG = 2'd0;
  localparam [1:0] SEG_CONV_WT  = 2'd1;
  localparam [1:0] SEG_FC_BIAS  = 2'd2;
  localparam [1:0] SEG_FCW      = 2'd3;

  // ---------------------------------------------------------------------------
  // 32-bit staging BRAM
  // ---------------------------------------------------------------------------
  (* ramstyle = "M10K" *)
  reg [31:0] mem [0:MEM_WORDS-1];

  reg [31:0]       mem_rdata_q;
  reg [31:0]       host_rdata_q;
  reg [31:0]       last_writedata_q;
  reg [3:0]        last_byteenable_q;
  reg              host_mem_rd_q;
  reg [MEM_AW-1:0] mem_rd_addr_q;
  reg              mem_rd_pending_q;
  reg              mem_rd_host_q;

  wire mem_sel    = chipselect && !address[MEM_AW];
  wire cfg_sel    = chipselect &&  address[MEM_AW];
  wire mem_wr_req = mem_sel &&  write;
  wire mem_rd_req = mem_sel &&  read;
  wire cfg_wr_req = cfg_sel &&  write;
  wire cfg_rd_req = cfg_sel &&  read;
  wire mem_addr_ok = (address[MEM_AW-1:0] < MEM_WORDS);
  wire mem_any_byte_en = |byteenable;
  wire cfg_lo_byte_en = |byteenable[1:0];

  // ---------------------------------------------------------------------------
  // Config registers
  // ---------------------------------------------------------------------------
  reg [15:0] conv_cfg_base_w;
  reg [15:0] conv_cfg_len_w;
  reg [15:0] conv_wt_base_w;
  reg [15:0] conv_wt_len_w;
  reg [15:0] fc_bias_base_w;
  reg [15:0] fc_bias_len_w;
  reg [15:0] fcw_base_w;
  reg [15:0] fcw_len_w;
  reg [15:0] image_base_w;
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

  reg [31:0] cfg_read_data;
  always @(*) begin
    cfg_read_data = 32'd0;
    case (address[4:0])
      REG_STATUS:        cfg_read_data = cfg_status_word;
      REG_CONV_CFG_BASE: cfg_read_data = conv_cfg_base_w;
      REG_CONV_CFG_LEN:  cfg_read_data = conv_cfg_len_w;
      REG_CONV_WT_BASE:  cfg_read_data = conv_wt_base_w;
      REG_CONV_WT_LEN:   cfg_read_data = conv_wt_len_w;
      REG_FC_BIAS_BASE:  cfg_read_data = fc_bias_base_w;
      REG_FC_BIAS_LEN:   cfg_read_data = fc_bias_len_w;
      REG_FCW_BASE:      cfg_read_data = fcw_base_w;
      REG_FCW_LEN:       cfg_read_data = fcw_len_w;
      REG_IMAGE_BASE:    cfg_read_data = image_base_w;
      REG_IMAGE_LEN:     cfg_read_data = image_len_w;
      REG_PREDICT:       cfg_read_data = {12'd0, predict_class_latched};
      REG_IF_ERROR:      cfg_read_data = interface_error;
      // Keep the legacy low-half register numbers reserved. Software should
      // read the *_HI aliases for the full 32-bit counters.
      REG_PROFILE_L1_LO:     cfg_read_data = 32'd0;
      REG_PROFILE_L1_HI:     cfg_read_data = accel_profile_l1_cycles;
      REG_PROFILE_L2_P0_LO:  cfg_read_data = 32'd0;
      REG_PROFILE_L2_P0_HI:  cfg_read_data = accel_profile_l2_p0_cycles;
      REG_PROFILE_L2_P1_LO:  cfg_read_data = 32'd0;
      REG_PROFILE_L2_P1_HI:  cfg_read_data = accel_profile_l2_p1_cycles;
      REG_PROFILE_L3_P0_LO:  cfg_read_data = 32'd0;
      REG_PROFILE_L3_P0_HI:  cfg_read_data = accel_profile_l3_p0_cycles;
      REG_PROFILE_L3_P1_LO:  cfg_read_data = 32'd0;
      REG_PROFILE_L3_P1_HI:  cfg_read_data = accel_profile_l3_p1_cycles;
      REG_PROFILE_FC_LO:     cfg_read_data = 32'd0;
      REG_PROFILE_FC_HI:     cfg_read_data = accel_profile_fc_cycles;
      REG_PROFILE_ARGMAX_LO: cfg_read_data = 32'd0;
      REG_PROFILE_ARGMAX_HI: cfg_read_data = accel_profile_argmax_cycles;
      REG_PROFILE_TOTAL_LO:  cfg_read_data = 32'd0;
      REG_PROFILE_TOTAL_HI:  cfg_read_data = accel_profile_total_cycles;
      REG_LAST_WRITE:     cfg_read_data = { last_byteenable_q, last_writedata_q[27:0] };
      REG_MAGIC:          cfg_read_data = CFG_MAGIC_WORD;
      default:           cfg_read_data = 32'd0;
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
  wire [31:0] accel_profile_l1_cycles;
  wire [31:0] accel_profile_l2_p0_cycles;
  wire [31:0] accel_profile_l2_p1_cycles;
  wire [31:0] accel_profile_l3_p0_cycles;
  wire [31:0] accel_profile_l3_p1_cycles;
  wire [31:0] accel_profile_fc_cycles;
  wire [31:0] accel_profile_argmax_cycles;
  wire [31:0] accel_profile_total_cycles;

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
    .predict_class(accel_predict_class),
    .profile_l1_cycles(accel_profile_l1_cycles),
    .profile_l2_p0_cycles(accel_profile_l2_p0_cycles),
    .profile_l2_p1_cycles(accel_profile_l2_p1_cycles),
    .profile_l3_p0_cycles(accel_profile_l3_p0_cycles),
    .profile_l3_p1_cycles(accel_profile_l3_p1_cycles),
    .profile_fc_cycles(accel_profile_fc_cycles),
    .profile_argmax_cycles(accel_profile_argmax_cycles),
    .profile_total_cycles(accel_profile_total_cycles)
  );

  // ---------------------------------------------------------------------------
  // Replay engine
  // ---------------------------------------------------------------------------
  reg [2:0] eng_state;
  reg [1:0] model_seg_idx;
  reg [15:0] seg_word_idx;
  reg [15:0] seg_word_count;

  function [15:0] model_seg_base;
    input [1:0] seg;
    begin
      case (seg)
        SEG_CONV_CFG: model_seg_base = conv_cfg_base_w;
        SEG_CONV_WT:  model_seg_base = conv_wt_base_w;
        SEG_FC_BIAS:  model_seg_base = fc_bias_base_w;
        default:      model_seg_base = fcw_base_w;
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
  wire issue_eng_read = (eng_state == ST_RD);
  wire [15:0] current_seg_base = (eng_mode == ENG_INFER) ? image_base_w
                                                         : model_seg_base(model_seg_idx);
  wire [15:0] current_seg_len  = (eng_mode == ENG_INFER) ? image_len_w
                                                         : model_seg_len(model_seg_idx);
  wire [15:0] current_word_addr = current_seg_base + seg_word_idx;
  wire eng_read_in_range = (current_word_addr < MEM_WORDS);

  always @(posedge clk) begin
    if (reset) begin
      mem_rdata_q      <= 32'd0;
      host_rdata_q     <= 32'd0;
      last_writedata_q  <= 32'd0;
      last_byteenable_q <= 4'd0;
      host_mem_rd_q    <= 1'b0;
      mem_rd_addr_q    <= {MEM_AW{1'b0}};
      mem_rd_pending_q <= 1'b0;
      mem_rd_host_q    <= 1'b0;
    end else begin
      host_mem_rd_q <= 1'b0;

      if (cfg_rd_req) begin
        host_rdata_q <= cfg_read_data;
      end

      if (host_mem_rd_q)
        host_rdata_q <= mem_rdata_q;

      if (mem_wr_req || cfg_wr_req) begin
        last_writedata_q  <= writedata;
        last_byteenable_q <= byteenable;
      end

      // The staged scratchpad expects full-word host writes. We only use
      // byteenable as a write-present qualifier here to keep the memory inferable
      // as block RAM on Cyclone V.
      if (mem_wr_req && !eng_busy && mem_addr_ok && mem_any_byte_en)
        mem[address[MEM_AW-1:0]] <= writedata;

      if (mem_rd_pending_q) begin
        mem_rdata_q <= mem[mem_rd_addr_q];
        host_mem_rd_q <= mem_rd_host_q;
      end

      mem_rd_pending_q <= 1'b0;

      if (issue_eng_read && eng_read_in_range) begin
        mem_rd_addr_q    <= current_word_addr[MEM_AW-1:0];
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
      conv_cfg_base_w       <= 16'd0;
      conv_cfg_len_w        <= 16'd45;
      conv_wt_base_w        <= 16'd45;
      conv_wt_len_w         <= 16'd225;
      fc_bias_base_w        <= 16'd270;
      fc_bias_len_w         <= 16'd10;
      fcw_base_w            <= 16'd280;
      fcw_len_w             <= 16'd864;
      image_base_w          <= 16'd1144;
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
    end else begin
      if (accel_predict_valid) begin
        predict_done          <= 1'b1;
        predict_class_latched <= accel_predict_class;
      end

      if (cfg_wr_req && cfg_lo_byte_en) begin
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
                eng_state      <= ST_RD;
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
                eng_state      <= ST_RD;
                seg_word_idx   <= 16'd0;
                seg_word_count <= image_len_w;
                predict_done   <= 1'b0;
              end
            end
          end

          REG_CONV_CFG_BASE: conv_cfg_base_w  <= writedata[15:0];
          REG_CONV_CFG_LEN:  conv_cfg_len_w   <= writedata[15:0];
          REG_CONV_WT_BASE:  conv_wt_base_w   <= writedata[15:0];
          REG_CONV_WT_LEN:   conv_wt_len_w    <= writedata[15:0];
          REG_FC_BIAS_BASE:  fc_bias_base_w   <= writedata[15:0];
          REG_FC_BIAS_LEN:   fc_bias_len_w    <= writedata[15:0];
          REG_FCW_BASE:      fcw_base_w       <= writedata[15:0];
          REG_FCW_LEN:       fcw_len_w        <= writedata[15:0];
          REG_IMAGE_BASE:    image_base_w     <= writedata[15:0];
          REG_IMAGE_LEN:     image_len_w      <= writedata[15:0];
          default: begin
          end
        endcase
      end

      case (eng_state)
        ST_IDLE: begin
        end

        ST_RD: begin
          if (!eng_read_in_range) begin
            interface_error[3] <= 1'b1;
            eng_mode           <= ENG_IDLE;
            eng_state          <= ST_IDLE;
          end else begin
            eng_state <= ST_WAIT_RD;
          end
        end

        ST_WAIT_RD: begin
          eng_state <= ST_SEND;
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
              eng_state    <= ST_RD;
            end
          end
        end

        ST_GAP: begin
          seg_word_count <= model_seg_len(model_seg_idx);
          eng_state      <= ST_RD;
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
    accel_load_data  = mem_rdata_q;
    accel_load_sel   = (eng_mode == ENG_INFER);
    accel_load_last  = (eng_state == ST_SEND) && (seg_word_idx == (seg_word_count - 16'd1));
  end

  // ---------------------------------------------------------------------------
  // Read response
  // ---------------------------------------------------------------------------
  always @(*) begin
    if (host_mem_rd_q)
      readdata = mem_rdata_q;
    else
      readdata = host_rdata_q;
  end

  assign debug_model_loaded   = model_loaded;
  assign debug_predict_done   = predict_done;
  assign debug_predict_class  = predict_class_latched;
  assign debug_interface_error = interface_error;

endmodule
