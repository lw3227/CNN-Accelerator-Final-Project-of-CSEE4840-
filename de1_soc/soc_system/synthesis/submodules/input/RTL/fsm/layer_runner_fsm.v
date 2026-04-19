// LayerRunnerFSM: single-layer / single-pass transaction controller.
//
// Conv mode (is_fc=0):
//   IDLE -> LOAD_CFG -> WAIT_CFG -> LOAD_WT -> WAIT_WT -> STREAM -> WAIT_DONE -> DONE_PULSE
//
// FC mode (is_fc=1):
//   IDLE -> LOAD_CFG -> WAIT_CFG -> STREAM -> WAIT_DONE -> DONE_PULSE
//
// SRAM_A interface uses data_sel (not op_type):
//   data_sel = 0 (CFG), 1 (WT), 2 (DATA)
//   Read/write direction derived by wrapper from layer_sel + data_sel.
//
// All state transitions driven by SRAM wrapper done signals.

module layer_runner_fsm (
  input  wire        clk,
  input  wire        rst_n,

  // --- TopFSM control ---
  input  wire        start,
  input  wire [1:0]  layer_sel,      // 00=L1, 01=L2, 10=L3
  input  wire        pass_id,
  input  wire        is_fc,
  output wire        busy,
  output reg         done,

  // --- SRAM_A wrapper control ---
  output reg         sram_a_start,
  output reg  [2:0]  sram_a_layer_sel,
  output reg  [1:0]  sram_a_data_sel,    // 0=CFG, 1=WT, 2=DATA
  output reg         sram_a_pass_id,
  input  wire        sram_a_done,

  // --- SRAM_B wrapper control ---
  output reg         sram_b_start,
  output reg  [2:0]  sram_b_layer_sel,
  output reg  [1:0]  sram_b_data_sel,
  output reg         sram_b_pass_id,
  input  wire        sram_b_done,

  // --- Conv path observation (auxiliary, NOT for transitions) ---
  input  wire        cfg_load_done,
  input  wire        wt_load_done,
  input  wire        pool_frame_done,
  input  wire        conv_frame_rearm,

  // --- FC path feedback ---
  input  wire        fc_done
);

  localparam [2:0] ST_IDLE      = 3'd0,
                   ST_LOAD_CFG  = 3'd1,
                   ST_WAIT_CFG  = 3'd2,
                   ST_LOAD_WT   = 3'd3,
                   ST_WAIT_WT   = 3'd4,
                   ST_STREAM    = 3'd5,
                   ST_WAIT_DONE = 3'd6,
                   ST_DONE      = 3'd7;

  localparam [1:0] SEL_CFG  = 2'd0,
                   SEL_WT   = 2'd1,
                   SEL_DATA = 2'd2;

  localparam [2:0] LSEL_L1 = 3'd1,
                   LSEL_L2 = 3'd2,
                   LSEL_L3 = 3'd3,
                   LSEL_FC = 3'd4;

  reg [2:0] state;

  // Debug-visible mirrors kept for TB/wave compatibility. They are no longer
  // used to drive transactions.
  reg [1:0] layer_sel_r;
  reg       pass_id_r;
  reg       is_fc_r;

  // TopFSM keeps layer_sel / pass_id / is_fc stable while a layer is running.
  // Use the live inputs for transaction control so the runner cannot start the
  // next layer with stale latched parameters.

  function [2:0] to_lsel;
    input [1:0] ls;
    input       fc;
    begin
      if (fc) to_lsel = LSEL_FC;
      else case (ls)
        2'b00:   to_lsel = LSEL_L1;
        2'b01:   to_lsel = LSEL_L2;
        2'b10:   to_lsel = LSEL_L3;
        default: to_lsel = LSEL_L1;
      endcase
    end
  endfunction

  // WAIT_DONE: accumulate done signals from both wrappers + pool
  reg sram_a_done_seen, sram_b_done_seen;
  reg pool_done_seen;
  reg frame_rearm_seen;

  assign busy = (state != ST_IDLE);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state            <= ST_IDLE;
      done             <= 1'b0;
      sram_a_start     <= 1'b0;
      sram_a_layer_sel <= 3'd0;
      sram_a_data_sel  <= 2'd0;
      sram_a_pass_id   <= 1'b0;
      sram_b_start     <= 1'b0;
      sram_b_layer_sel <= 3'd0;
      sram_b_data_sel  <= 2'd0;
      sram_b_pass_id   <= 1'b0;
      layer_sel_r      <= 2'b00;
      pass_id_r        <= 1'b0;
      is_fc_r          <= 1'b0;
      sram_a_done_seen <= 1'b0;
      sram_b_done_seen <= 1'b0;
      pool_done_seen   <= 1'b0;
      frame_rearm_seen <= 1'b0;
    end else begin
      // Clear one-cycle pulses
      sram_a_start <= 1'b0;
      sram_b_start <= 1'b0;
      done         <= 1'b0;

      case (state)
        // ---------------------------------------------------------
        ST_IDLE: begin
          if (start) begin
            layer_sel_r <= layer_sel;
            pass_id_r   <= pass_id;
            is_fc_r     <= is_fc;
            state       <= ST_LOAD_CFG;
          end
        end

        // ---------------------------------------------------------
        ST_LOAD_CFG: begin
          sram_a_start     <= 1'b1;
          sram_a_layer_sel <= to_lsel(layer_sel, is_fc);
          sram_a_data_sel  <= SEL_CFG;
          sram_a_pass_id   <= pass_id;
          sram_a_done_seen <= 1'b0;
          state            <= ST_WAIT_CFG;
        end

        ST_WAIT_CFG: begin
          if (sram_a_done) sram_a_done_seen <= 1'b1;
          if (is_fc) begin
            if ((sram_a_done_seen || sram_a_done) && cfg_load_done) begin
              sram_a_done_seen <= 1'b0;
              state <= ST_STREAM;   // FC skips LOAD_WT
            end
          end else begin
            if (sram_a_done)
              state <= ST_LOAD_WT;
          end
        end

        // ---------------------------------------------------------
        ST_LOAD_WT: begin
          sram_a_start     <= 1'b1;
          sram_a_layer_sel <= to_lsel(layer_sel, 1'b0);
          sram_a_data_sel  <= SEL_WT;
          sram_a_pass_id   <= pass_id;
          state            <= ST_WAIT_WT;
        end

        ST_WAIT_WT: begin
          if (sram_a_done)
            state <= ST_STREAM;
        end

        // ---------------------------------------------------------
        ST_STREAM: begin
          sram_a_done_seen <= 1'b0;
          sram_b_done_seen <= 1'b0;
          pool_done_seen   <= 1'b0;
          frame_rearm_seen <= 1'b0;

          if (is_fc) begin
            // FC: SRAM_A reads interleaved weight, SRAM_B reads packed data
            sram_a_start     <= 1'b1;
            sram_a_layer_sel <= LSEL_FC;
            sram_a_data_sel  <= SEL_WT;
            sram_a_pass_id   <= 1'b0;

            sram_b_start     <= 1'b1;
            sram_b_layer_sel <= LSEL_FC;
            sram_b_data_sel  <= SEL_DATA;
            sram_b_pass_id   <= 1'b0;
          end else begin
            // Conv: start DATA transaction on both SRAMs
            // L1: pixels stream directly from external load_data (no SRAM_A read)
            // L2/L3: read DATA from SRAM_A (or SRAM_B)
            if (layer_sel != 2'b00) begin
              sram_a_start     <= 1'b1;
              sram_a_layer_sel <= to_lsel(layer_sel, 1'b0);
              sram_a_data_sel  <= SEL_DATA;
              sram_a_pass_id   <= pass_id;
            end

            sram_b_start     <= 1'b1;
            sram_b_layer_sel <= to_lsel(layer_sel, 1'b0);
            sram_b_data_sel  <= SEL_DATA;
            sram_b_pass_id   <= pass_id;
          end

          state <= ST_WAIT_DONE;
        end

        // ---------------------------------------------------------
        ST_WAIT_DONE: begin
          if (sram_a_done) sram_a_done_seen <= 1'b1;
          if (sram_b_done) sram_b_done_seen <= 1'b1;
          if (pool_frame_done) pool_done_seen <= 1'b1;
          if (conv_frame_rearm) frame_rearm_seen <= 1'b1;

          // Both wrapper dones must arrive
          if (is_fc) begin
            if (fc_done &&
                (sram_a_done_seen || sram_a_done) &&
                (sram_b_done_seen || sram_b_done))
              state <= ST_DONE;
          end else if (layer_sel == 2'b00) begin
            // L1: pixels stream from external (no SRAM_A read), only wait
            // for SRAM_B (pool writeback) and conv_frame_rearm.
            if ((sram_b_done_seen || sram_b_done) &&
                (frame_rearm_seen || conv_frame_rearm))
              state <= ST_DONE;
          end else begin
            if ((sram_a_done_seen || sram_a_done) &&
                (sram_b_done_seen || sram_b_done) &&
                (frame_rearm_seen || conv_frame_rearm))
              state <= ST_DONE;
          end
        end

        // ---------------------------------------------------------
        ST_DONE: begin
          done  <= 1'b1;
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
