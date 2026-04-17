`timescale 1ns / 1ps

// cnn_mmio_demo_top
// -----------------
// FPGA-only bring-up shell for DE1-SoC style boards.
//
// This wrapper does not replace the intended HPS/MMIO path. It exists so we
// can expose a few useful status signals on board IO while the real HPS system
// is being assembled in Platform Designer.
//
// Intended usage:
// - drive clk from CLOCK_50
// - drive reset from a push button
// - optionally connect the mmio_* ports to a Qsys/Platform Designer bridge or
//   to a lightweight debug fabric
// - observe model_loaded / predict_done / predict_class on LEDs

module cnn_mmio_demo_top (
  input  wire        CLOCK_50,
  input  wire [3:0]  KEY,
  output wire [9:0]  LEDR,

  input  wire [19:0] mmio_address,
  input  wire        mmio_chipselect,
  input  wire        mmio_write,
  input  wire [15:0] mmio_writedata,
  output wire [15:0] mmio_readdata
);

  wire reset = ~KEY[0];
  wire        model_loaded_led;
  wire        predict_done_led;
  wire [3:0]  predict_class_led;
  wire [15:0] error_word;

  cnn_mmio_interface u_cnn_mmio_interface (
    .clk       (CLOCK_50),
    .reset     (reset),
    .writedata (mmio_writedata),
    .write     (mmio_write),
    .chipselect(mmio_chipselect),
    .address   (mmio_address),
    .readdata  (mmio_readdata)
  );

  // Read-only mirrors for quick board bring-up. These are not meant to replace
  // software status reads; they simply make it obvious that the wrapper is
  // alive and which class was last latched.
  assign model_loaded_led  = u_cnn_mmio_interface.model_loaded;
  assign predict_done_led  = u_cnn_mmio_interface.predict_done;
  assign predict_class_led = u_cnn_mmio_interface.predict_class_latched;
  assign error_word        = u_cnn_mmio_interface.interface_error;

  assign LEDR[0]   = ~KEY[0];
  assign LEDR[1]   = model_loaded_led;
  assign LEDR[2]   = predict_done_led;
  assign LEDR[6:3] = predict_class_led;
  assign LEDR[9:7] = error_word[2:0];

endmodule
