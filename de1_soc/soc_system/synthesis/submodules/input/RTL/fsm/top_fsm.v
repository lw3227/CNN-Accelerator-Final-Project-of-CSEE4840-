// TopFSM: network-level sequencer.
//
// MODEL_LOAD (one-time): host sends cfg → weight → image via load_data bus
// INFER (repeatable): L1 → L2p0 → L2p1 → L3p0 → L3p1 → FC → ARGMAX → READY
//
// Preload follows SRAM_CONNECTION_NOTES layer0 convention:
//   PL_CFG   → sram_a_start(layer0, CFG_READ)
//   PL_WT    → sram_a_start(layer0, WT_READ)
//   PL_PIXEL → sram_a_start(layer0, DATA_READ)
// Each segment ends when host asserts load_last on the valid&&ready beat.

module top_fsm #(
  parameter integer ACC_W        = 32,  // FC accumulator width (matches SRAM/cfg 32-bit path)
  parameter integer OUT_CHANNELS = 10   // FC output channels (0-9 gesture classes)
)(
  input  wire        clk,
  input  wire        rst_n,

  // --- External data port (32-bit parallel, valid/ready) ---
  input  wire        load_sel,       // 0=model, 1=image
  input  wire        load_valid,
  input  wire [31:0] load_data,
  input  wire        load_last,
  output wire        load_ready,

  // --- External status ---
  output wire        busy,
  output reg         predict_valid,
  output reg  [3:0]  predict_class,  // 10-class gesture id (0-9)

  // --- LayerRunnerFSM control ---
  output reg         runner_start,
  output reg  [1:0]  runner_layer_sel,
  output reg         runner_pass_id,
  output reg         runner_is_fc,
  input  wire        runner_done,

  // --- SRAM_A preload control (active during MODEL_LOAD / LOAD_IMAGE) ---
  // During inference, SRAM_A is driven by LayerRunnerFSM via system_top MUX.
  output reg         sram_a_start,
  output reg  [2:0]  sram_a_layer_sel,
  output reg  [1:0]  sram_a_data_sel,   // 0=CFG, 1=WT, 2=DATA
  input  wire        sram_a_done,

  // --- Preload write data (directly forwarded to SRAM_A wrapper write port) ---
  output wire        preload_wr_valid,
  output wire [31:0] preload_wr_data,
  input  wire        preload_wr_ready,  // backpressure from SRAM_A wrapper

  // --- L1 pixel bypass: load_data streams directly to conv ---
  output reg         pixel_stream_active,  // high during L1 pixel streaming
  input  wire        conv_adapter_up_ready, // backpressure from conv_data_adapter
  input  wire        conv_frame_rearm,      // from Conv1_top: all pixels processed

  // --- FC accumulator results (packed vector, LSB = channel 0) ---
  input  wire [OUT_CHANNELS*ACC_W-1:0] fc_acc_vec
);

  // ---------------------------------------------------------------
  // State encoding
  // ---------------------------------------------------------------
  localparam [4:0] ST_IDLE        = 5'd0,
                   ST_PL_CFG      = 5'd1,   // MODEL_LOAD sub-state: conv cfg
                   ST_PL_CFG_W    = 5'd2,
                   ST_PL_WT       = 5'd3,   // MODEL_LOAD sub-state: conv weight
                   ST_PL_WT_W     = 5'd4,
                   ST_PL_PIXEL    = 5'd5,
                   ST_PL_PIXEL_W  = 5'd6,
                   ST_READY       = 5'd7,
                   ST_L1          = 5'd8,
                   ST_L2_P0       = 5'd9,
                   ST_L2_P1       = 5'd10,
                   ST_L3_P0       = 5'd11,
                   ST_L3_P1       = 5'd12,
                   ST_FC          = 5'd13,
                   ST_ARGMAX      = 5'd14,
                   ST_PL_FC_CFG   = 5'd15,  // MODEL_LOAD: 10 FC bias words into SRAM_A@0x111
                   ST_PL_FC_CFG_W = 5'd16,
                   ST_PL_FCW      = 5'd17,  // MODEL_LOAD: 864 host words into SRAM_FCW packer
                   ST_PL_FCW_W    = 5'd18;

  // SRAM_A layer0 preload encodings
  localparam [2:0] LSEL_LAYER0 = 3'b000;
  localparam [1:0] SEL_CFG  = 2'd0,
                   SEL_WT   = 2'd1,
                   SEL_DATA = 2'd2,
                   SEL_FCW  = 2'd3;

  reg [4:0] state;
  reg       preload_active;   // data forwarding enabled
  reg       load_last_seen;   // current segment's load_last received
  reg       model_loaded;     // model has been loaded at least once
  reg       preload_sram_done; // latched sram_a_done during preload wait
  reg       runner_started;    // prevents repeated runner_start pulses

  // ---------------------------------------------------------------
  // Preload data forwarding / L1 pixel bypass
  // ---------------------------------------------------------------
  // CFG/WT preload: forward load_data to SRAM_A write port
  // L1 pixel streaming: load_data bypasses SRAM_A, goes directly to conv
  assign preload_wr_valid = preload_active && load_valid;
  assign preload_wr_data  = load_data;
  assign load_ready       = (preload_active      && preload_wr_ready)
                          | (pixel_stream_active && conv_adapter_up_ready);

  assign busy = (state != ST_IDLE) && (state != ST_READY);

  // ---------------------------------------------------------------
  // 10-way argmax (combinational sequential reduction)
  // Strict-greater compare: on ties the lower index wins (matches the
  // 3-class >= convention used previously).
  // ---------------------------------------------------------------
  reg [3:0]                  argmax_idx;
  reg signed [ACC_W-1:0]     argmax_val;
  integer                    ai;
  always @(*) begin
    argmax_idx = 4'd0;
    argmax_val = $signed(fc_acc_vec[0 +: ACC_W]);
    for (ai = 1; ai < OUT_CHANNELS; ai = ai + 1) begin
      if ($signed(fc_acc_vec[ai*ACC_W +: ACC_W]) > argmax_val) begin
        argmax_val = $signed(fc_acc_vec[ai*ACC_W +: ACC_W]);
        argmax_idx = ai[3:0];
      end
    end
  end

  // ---------------------------------------------------------------
  // FSM
  // ---------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state            <= ST_IDLE;
      predict_valid    <= 1'b0;
      predict_class    <= 4'd0;
      runner_start     <= 1'b0;
      runner_layer_sel <= 2'b00;
      runner_pass_id   <= 1'b0;
      runner_is_fc     <= 1'b0;
      sram_a_start     <= 1'b0;
      sram_a_layer_sel <= 3'd0;
      sram_a_data_sel   <= 2'b00;
      preload_active   <= 1'b0;
      load_last_seen   <= 1'b0;
      model_loaded     <= 1'b0;
      preload_sram_done <= 1'b0;
      runner_started   <= 1'b0;
      pixel_stream_active <= 1'b0;
    end else begin
      // Default: clear one-cycle pulses
      sram_a_start <= 1'b0;
      runner_start <= 1'b0;
      predict_valid <= 1'b0;

      // Track load_last during preload (fires on valid && load_last)
      if (preload_active && load_valid && load_last)
        load_last_seen <= 1'b1;

      // Latch sram_a_done during preload wait (done is a 1-cycle pulse)
      if (preload_active && sram_a_done)
        preload_sram_done <= 1'b1;

      case (state)
        // ---------------------------------------------------------
        ST_IDLE: begin
          preload_active <= 1'b0;
          if (load_valid && load_sel == 1'b0) begin
            // Host wants to load model → start MODEL_LOAD
            state <= ST_PL_CFG;
          end
        end

        // ---------------------------------------------------------
        // MODEL_LOAD: 3 sub-states (PL_CFG → PL_WT → PL_PIXEL)
        // ---------------------------------------------------------
        ST_PL_CFG: begin
          sram_a_start      <= 1'b1;
          sram_a_layer_sel  <= LSEL_LAYER0;
          sram_a_data_sel   <= SEL_CFG;
          preload_active    <= 1'b1;
          load_last_seen    <= 1'b0;
          preload_sram_done <= 1'b0;
          state             <= ST_PL_CFG_W;
        end

        ST_PL_CFG_W: begin
          if (load_last_seen && (sram_a_done || preload_sram_done)) begin
            preload_active <= 1'b0;
            if (!load_valid) begin
              load_last_seen <= 1'b0;
              state          <= ST_PL_WT;
            end
          end
        end

        ST_PL_WT: begin
          sram_a_start      <= 1'b1;
          sram_a_layer_sel  <= LSEL_LAYER0;
          sram_a_data_sel   <= SEL_WT;
          preload_active    <= 1'b1;
          load_last_seen    <= 1'b0;
          preload_sram_done <= 1'b0;
          state             <= ST_PL_WT_W;
        end

        ST_PL_WT_W: begin
          if (load_last_seen && (sram_a_done || preload_sram_done)) begin
            preload_active <= 1'b0;
            if (!load_valid) begin
              load_last_seen <= 1'b0;
              // Continue preload: FC bias words, then FCW weight packed stream.
              state          <= ST_PL_FC_CFG;
            end
          end
        end

        // FC bias: 10 x 32-bit words written to SRAM_A at FC_CFG_BASE (0x111).
        // Uses LAYER_FC + SEL_CFG; controller enables both read/write modes,
        // and preload_mode in system_top gates the write path while blocking
        // conv_pool_valid so only the host write actually fires.
        ST_PL_FC_CFG: begin
          sram_a_start      <= 1'b1;
          sram_a_layer_sel  <= 3'd4;          // LAYER_FC
          sram_a_data_sel   <= SEL_CFG;
          preload_active    <= 1'b1;
          load_last_seen    <= 1'b0;
          preload_sram_done <= 1'b0;
          state             <= ST_PL_FC_CFG_W;
        end

        ST_PL_FC_CFG_W: begin
          if (load_last_seen && (sram_a_done || preload_sram_done)) begin
            preload_active <= 1'b0;
            if (!load_valid) begin
              load_last_seen <= 1'b0;
              state          <= ST_PL_FCW;
            end
          end
        end

        // FC weight: 864 x 32-bit words packed by fcw_preload_packer into
        // 288 x 80-bit words inside SRAM_FCW.
        ST_PL_FCW: begin
          sram_a_start      <= 1'b1;
          sram_a_layer_sel  <= LSEL_LAYER0;   // LAYER_PRELOAD
          sram_a_data_sel   <= SEL_FCW;
          preload_active    <= 1'b1;
          load_last_seen    <= 1'b0;
          preload_sram_done <= 1'b0;
          state             <= ST_PL_FCW_W;
        end

        ST_PL_FCW_W: begin
          if (load_last_seen && (sram_a_done || preload_sram_done)) begin
            preload_active <= 1'b0;
            if (!load_valid) begin
              load_last_seen <= 1'b0;
              // MODEL_LOAD complete.
              model_loaded   <= 1'b1;
              state          <= ST_READY;
            end
          end
        end

        // ST_PL_PIXEL / ST_PL_PIXEL_W: removed — pixels now stream directly
        // to conv_data_adapter via system_top during ST_L1.

        // ---------------------------------------------------------
        ST_READY: begin
          preload_active <= 1'b0;
          if (load_valid && !load_last && load_sel == 1'b1) begin
            // Host wants to send image → enter L1 (pixels stream directly)
            state <= ST_L1;
          end else if (load_valid && !load_last && load_sel == 1'b0) begin
            // Host wants to reload model
            model_loaded <= 1'b0;
            state <= ST_PL_CFG;
          end
        end

        // ---------------------------------------------------------
        // Inference: L1 → L2p0 → L2p1 → L3p0 → L3p1 → FC → ARGMAX
        // Each state: pulse runner_start once, then wait for runner_done.
        // runner_started prevents repeated start pulses while waiting.
        // ---------------------------------------------------------
        ST_L1: begin
          if (!runner_started) begin
            runner_start     <= 1'b1;
            runner_started   <= 1'b1;
            runner_layer_sel <= 2'b00;
            runner_pass_id   <= 1'b0;
            runner_is_fc     <= 1'b0;
            pixel_stream_active <= 1'b1;  // route load_data directly to conv
          end
          if (runner_done) begin
            state <= ST_L2_P0;
            runner_started <= 1'b0;
            pixel_stream_active <= 1'b0;
          end
        end

        ST_L2_P0: begin
          if (!runner_started) begin
            runner_start     <= 1'b1;
            runner_started   <= 1'b1;
            runner_layer_sel <= 2'b01;
            runner_pass_id   <= 1'b0;
            runner_is_fc     <= 1'b0;
          end
          if (runner_done) begin state <= ST_L2_P1; runner_started <= 1'b0; end
        end

        ST_L2_P1: begin
          if (!runner_started) begin
            runner_start     <= 1'b1;
            runner_started   <= 1'b1;
            runner_layer_sel <= 2'b01;
            runner_pass_id   <= 1'b1;
            runner_is_fc     <= 1'b0;
          end
          if (runner_done) begin state <= ST_L3_P0; runner_started <= 1'b0; end
        end

        ST_L3_P0: begin
          if (!runner_started) begin
            runner_start     <= 1'b1;
            runner_started   <= 1'b1;
            runner_layer_sel <= 2'b10;
            runner_pass_id   <= 1'b0;
            runner_is_fc     <= 1'b0;
          end
          if (runner_done) begin state <= ST_L3_P1; runner_started <= 1'b0; end
        end

        ST_L3_P1: begin
          if (!runner_started) begin
            runner_start     <= 1'b1;
            runner_started   <= 1'b1;
            runner_layer_sel <= 2'b10;
            runner_pass_id   <= 1'b1;
            runner_is_fc     <= 1'b0;
          end
          if (runner_done) begin state <= ST_FC; runner_started <= 1'b0; end
        end

        ST_FC: begin
          if (!runner_started) begin
            runner_start     <= 1'b1;
            runner_started   <= 1'b1;
            runner_layer_sel <= 2'b00;
            runner_pass_id   <= 1'b0;
            runner_is_fc     <= 1'b1;
          end
          if (runner_done) begin state <= ST_ARGMAX; runner_started <= 1'b0; end
        end

        // ---------------------------------------------------------
        ST_ARGMAX: begin
          // 10-way argmax: strict-greater wins, so lower index wins on tie.
          predict_class <= argmax_idx;
          predict_valid <= 1'b1;
          state         <= ST_READY;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
