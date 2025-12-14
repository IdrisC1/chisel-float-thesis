// // // Copyright 2018 ETH Zurich and University of Bologna.
// // // Copyright and related rights are licensed under the Solderpad Hardware
// // // License, Version 0.51 (the “License”); you may not use this file except in
// // // compliance with the License.  You may obtain a copy of the License at
// // // http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// // // or agreed to in writing, software, hardware and materials distributed under
// // // this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// // // CONDITIONS OF ANY KIND, either express or implied. See the License for the
// // // specific language governing permissions and limitations under the License.
// // ////////////////////////////////////////////////////////////////////////////////
// // // Company:        IIS @ ETHZ - Federal Institute of Technology               //
// // //                                                                            //
// // // Engineers:      Lei Li      lile@iis.ee.ethz.ch                            //
// // //                                                                            //
// // // Additional contributions by:                                               //
// // //                                                                            //
// // //                                                                            //
// // //                                                                            //
// // // Create Date:    10/04/2018                                                 //
// // // Design Name:    FPU                                                        //
// // // Module Name:    nrbd_nrsc_mvp.sv                                           //
// // // Project Name:   Private FPU                                                //
// // // Language:       SystemVerilog                                              //
// // //                                                                            //
// // // Description:   non restroring binary  divisior/ square root                //
// // //                                                                            //
// // // Revision Date:  12/04/2018                                                 //
// // //                 Lei Li                                                     //
// // //                 To address some requirements by Stefan and add low power   //
// // //                 control for special cases                                  //
// // //                                                                            //
// // ////////////////////////////////////////////////////////////////////////////////

// // // import defs_div_sqrt_mvp::*;

// module nrbd_nrsc_mvp #(
//   parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
//   parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00,// Full precision as default
//   parameter logic [2:0] Iteration_unit_num_S  = 3'b011, //Default 4 (encoded in 3 bits)

  
//   parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
//   parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
//   parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)

//  )
//   (//Input
//    input logic                                 Clk_CI,
//    input logic                                 Rst_RBI,
//    input logic                                 Div_start_SI,
//   //  input logic                                 Sqrt_start_SI,
//    input logic                                 Start_SI,
//    input logic                                 Kill_SI,
//    input logic                                 Special_case_SBI,
//    input logic                                 Special_case_dly_SBI,
//   //  input logic [C_PC-1:0]                      Precision_ctl_SI,
//   //  input logic [1:0]                           Format_sel_SI,
//   //  input logic [C_MANT_FP64:0]                 Mant_a_DI,
//   //  input logic [C_MANT_FP64:0]                 Mant_b_DI,
//   //  input logic [C_EXP_FP64:0]                  Exp_a_DI,
//   //  input logic [C_EXP_FP64:0]                  Exp_b_DI,
//    input logic [MAN_BITS:0]                    Mant_a_DI,
//    input logic [MAN_BITS:0]                    Mant_b_DI,
//    input logic [EXP_BITS:0]                    Exp_a_DI,
//    input logic [EXP_BITS:0]                    Exp_b_DI,
//   //output
//    output logic                                Div_enable_SO,
//   //  output logic                                Sqrt_enable_SO,

//   //  output logic                                Full_precision_SO,
//   //  output logic                                FP32_SO,
//   //  output logic                                FP64_SO,
//   //  output logic                                FP16_SO,
//   //  output logic                                FP16ALT_SO,
//    output logic                                Ready_SO,
//    output logic                                Done_SO,
//   //  output logic  [C_MANT_FP64+4:0]             Mant_z_DO,
//   //  output logic [C_EXP_FP64+1:0]               Exp_z_DO
//    output logic  [MAN_BITS+4:0]                Mant_z_DO,
//    output logic [EXP_BITS+1:0]                 Exp_z_DO
//   );


//   // localparam int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat);
//   // localparam int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat);
//   // localparam int unsigned WIDTH = fpnew_pkg_snax::width(FpFormat);

//   logic                                     Div_start_dly_S;  //Sqrt_start_dly_S;


// control_mvp  #(
//   .FpFormat (FpFormat),
//   .PRECISION_CTRL (PRECISION_CTRL),
//   .Iteration_unit_num_S (Iteration_unit_num_S)
// ) control_U0
// (  .Clk_CI                                   (Clk_CI                          ),
//    .Rst_RBI                                  (Rst_RBI                         ),
//    .Div_start_SI                             (Div_start_SI                    ),
//   //  .Sqrt_start_SI                            (Sqrt_start_SI                   ),
//    .Start_SI                                 (Start_SI                        ),
//    .Kill_SI                                  (Kill_SI                         ),
//    .Special_case_SBI                         (Special_case_SBI                ),
  //  .Special_case_dly_SBI                     (Special_case_dly_SBI            ),
//   //  .Precision_ctl_SI                         (Precision_ctl_SI                ),
//   //  .Format_sel_SI                            (Format_sel_SI                   ),
//    .Numerator_DI                             (Mant_a_DI                       ),
//    .Exp_num_DI                               (Exp_a_DI                        ),
//    .Denominator_DI                           (Mant_b_DI                       ),
//    .Exp_den_DI                               (Exp_b_DI                        ),
//    .Div_start_dly_SO                         (Div_start_dly_S                 ),
//   //  .Sqrt_start_dly_SO                        (Sqrt_start_dly_S                ),
//    .Div_enable_SO                            (Div_enable_SO                   ),
//   //  .Sqrt_enable_SO                           (Sqrt_enable_SO                  ),
//   //  .Full_precision_SO                        (Full_precision_SO               ),
//   //  .FP32_SO                                  (FP32_SO                         ),
//   //  .FP64_SO                                  (FP64_SO                         ),
//   //  .FP16_SO                                  (FP16_SO                         ),
//   //  .FP16ALT_SO                               (FP16ALT_SO                      ),
//    .Ready_SO                                 (Ready_SO                        ),
//    .Done_SO                                  (Done_SO                         ),
//    .Mant_result_prenorm_DO                   (Mant_z_DO                       ),
//    .Exp_result_prenorm_DO                    (Exp_z_DO                        )
// );



// endmodule

// nrbd_nrsc_mvp.sv
// Wrapper for Pipelined Goldschmidt Divider
// Replaces the iterative Non-Restoring Divider

module nrbd_nrsc_mvp #(
  parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
//   parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, 
  // parameter logic [2:0] Iteration_unit_num_S  = 3'b011, // Unused in Goldschmidt but kept for interface compatibility
  
  // Goldschmidt Config
  parameter int unsigned GUARD_BITS = 11,
  parameter int ROM_ADDR_BITS = 8, 

  parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
  parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
  parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)
 )
  (//Input
   input logic                                 clk,
   input logic                                 Rst_RBI,
   input logic                                 Div_start_SI,
   input logic                                 Start_SI, // General start
   input logic                                 Kill_SI,
   
   // Passthrough signals from Pre-process
  //  input logic                                 Special_case_SBI,
  //  input logic [2:0]                           RM_SI, // Rounding Mode input
   input logic                                 Sign_z_SI,
   input logic                                 Inf_a_SI, Inf_b_SI,
   input logic                                 Zero_a_SI, Zero_b_SI,
   input logic                                 NaN_a_SI, NaN_b_SI, SNaN_SI,

   // Normalized Inputs
   input logic [MAN_BITS:0]                    Mant_a_DI,
   input logic [MAN_BITS:0]                    Mant_b_DI,
   input logic [EXP_BITS:0]                    Exp_a_DI,
   input logic [EXP_BITS:0]                    Exp_b_DI,

  // Outputs to Normalizer
   output logic                                Div_enable_SO, // Used as "Valid" for norm
   output logic                                Ready_SO,      // Backpressure to Pre-process
   output logic                                Done_SO,       // Pulse when complete

   output logic  [MAN_BITS+4:0]                Mant_z_DO,
   output logic  [EXP_BITS+1:0]                 Exp_z_DO,
   
   // Delayed Metadata outputs to Normalizer
  //  output logic [2:0]                          RM_DO,
   output logic                                Sign_z_DO,
  //  output logic                                Special_case_SO,
   output logic                                Inf_a_SO, Inf_b_SO,
   output logic                                Zero_a_SO, Zero_b_SO,
   output logic                                NaN_a_SO, NaN_b_SO, SNaN_SO
  );




  // ---------------------------------------------------------
  // Input Alignment Logic (Fixing the 1-cycle mismatch)
  // ---------------------------------------------------------
  logic start_dly_q;

  // Delay the start signal by 1 cycle to match Pre-process data latency
  always_ff @(posedge clk or negedge Rst_RBI) begin
      if (!Rst_RBI) begin
          start_dly_q <= 1'b0;
      end else if (Kill_SI) begin
          start_dly_q <= 1'b0;
      end else begin
          start_dly_q <= Div_start_SI;
      end
  end
  // ---------------------------------------------------------
  // Instantiate Goldschmidt Pipeline
  // ---------------------------------------------------------
  
  logic valid_out;
  
//   fp_div_Goldschmidt #(
//       .FpFormat     (FpFormat),
//     //   .PRECISION_CTRL ('h00), 
//       .GUARD_BITS   (GUARD_BITS),
//       .ROM_ADDR_BITS(ROM_ADDR_BITS)
//   ) goldschmidt_core (
//       .clk          (clk),
//       .rst_ni         (Rst_RBI),
//       .kill_i         (Kill_SI),
//       .start_i        (start_dly_q), 
      
//       .mant_a_i       (Mant_a_DI),
//       .mant_b_i       (Mant_b_DI),
//       .exp_a_i        (Exp_a_DI),
//       .exp_b_i        (Exp_b_DI),
      
//       // Pass metadata
//       // .rm_i           (RM_SI),
//       .sign_z_i       (Sign_z_SI),
//       // .special_case_i (Special_case_SBI),
//       .inf_a_i        (Inf_a_SI), .inf_b_i (Inf_b_SI),
//       .zero_a_i       (Zero_a_SI), .zero_b_i (Zero_b_SI),
//       .nan_a_i        (NaN_a_SI), .nan_b_i (NaN_b_SI), .snan_i (SNaN_SI),

//       // Outputs
//       .valid_o        (valid_out),
//       .mant_res_o     (Mant_z_DO),
//       .exp_res_o      (Exp_z_DO),
      
//       // .rm_o           (RM_DO),
//       .sign_z_o       (Sign_z_DO),
//       // .special_case_o (Special_case_SO),
//       .inf_a_o        (Inf_a_SO), .inf_b_o (Inf_b_SO),
//       .zero_a_o       (Zero_a_SO), .zero_b_o (Zero_b_SO),
//       .nan_a_o        (NaN_a_SO), .nan_b_o (NaN_b_SO), .snan_o (SNaN_SO)
//   );

//   // ---------------------------------------------------------
//   // Output Mapping
//   // ---------------------------------------------------------
  
//   // Pipeline is always ready (unless you add stall logic)
//   assign Ready_SO = 1'b1; 
  
//   // Done and Enable are synonymous in a pipeline output context
//   assign Done_SO       = valid_out;
//   assign Div_enable_SO = valid_out;

// endmodule

  fp_div_Goldschmidt #(
      .FpFormat     (FpFormat),
    //   .PRECISION_CTRL ('h00), 
      .GUARD_BITS   (GUARD_BITS),
      .ROM_ADDR_BITS(ROM_ADDR_BITS)
  ) goldschmidt_core (
      .clk          (clk),
      .rst_ni         (Rst_RBI),
      .kill_i         (Kill_SI),
      .start_i        (start_dly_q), 
      
      .mant_a_i       (Mant_a_DI),
      .mant_b_i       (Mant_b_DI),
      .exp_a_i        (Exp_a_DI),
      .exp_b_i        (Exp_b_DI),
      
      // Pass metadata
      // .rm_i           (RM_SI),
      .sign_z_i       (Sign_z_SI),
      // .special_case_i (Special_case_SBI),
      .inf_a_i        (Inf_a_SI), .inf_b_i (Inf_b_SI),
      .zero_a_i       (Zero_a_SI), .zero_b_i (Zero_b_SI),
      .nan_a_i        (NaN_a_SI), .nan_b_i (NaN_b_SI), .snan_i (SNaN_SI),

      // Outputs
      .valid_o        (valid_out),
      .mant_res_o     (Mant_z_DO),
      .exp_res_o      (Exp_z_DO),
      
      // .rm_o           (RM_DO),
      .sign_z_o       (Sign_z_DO),
      // .special_case_o (Special_case_SO),
      .inf_a_o        (Inf_a_SO), .inf_b_o (Inf_b_SO),
      .zero_a_o       (Zero_a_SO), .zero_b_o (Zero_b_SO),
      .nan_a_o        (NaN_a_SO), .nan_b_o (NaN_b_SO), .snan_o (SNaN_SO)
  );

  // ---------------------------------------------------------
  // Output Mapping
  // ---------------------------------------------------------
  
  // Pipeline is always ready (unless you add stall logic)
  assign Ready_SO = 1'b1; 
  
  // Done and Enable are synonymous in a pipeline output context
  assign Done_SO       = valid_out;
  assign Div_enable_SO = valid_out;
endmodule



// // nrbd_nrsc_mvp.sv
// // Wrapper for Goldschmidt Divider
// // Fixed: Pipeline Delay synchronization (Depth + 1)

// module nrbd_nrsc_mvp #(
//   parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
//   parameter int unsigned GUARD_BITS = 11,
//   parameter int ROM_ADDR_BITS = 8, 

//   parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
//   parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
//   parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)
//  )
//   (//Input
//    input logic                                 clk,
//    input logic                                 Rst_RBI,
//    input logic                                 Div_start_SI,
//    input logic                                 Start_SI, 
//    input logic                                 Kill_SI,
   
//    // Pre-process Signals
//    input logic                                 Sign_z_SI,
//    input logic                                 Inf_a_SI, Inf_b_SI,
//    input logic                                 Zero_a_SI, Zero_b_SI,
//    input logic                                 NaN_a_SI, NaN_b_SI, SNaN_SI,

//    // Normalized Inputs
//    input logic [MAN_BITS:0]                    Mant_a_DI,
//    input logic [MAN_BITS:0]                    Mant_b_DI,
//    input logic [EXP_BITS:0]                    Exp_a_DI,
//    input logic [EXP_BITS:0]                    Exp_b_DI,

//    // Outputs to Normalizer
//    output logic                                Div_enable_SO, 
//    output logic                                Ready_SO,
//    output logic                                Done_SO,       

//    output logic  [MAN_BITS+4:0]                Mant_z_DO,     
//    output logic  [EXP_BITS+1:0]                Exp_z_DO,
   
//    // Delayed Operands for Back-Multiplication
//    output logic  [MAN_BITS:0]                  Mant_a_pipe_DO,
//    output logic  [MAN_BITS:0]                  Mant_b_pipe_DO,

//    // Metadata
//    output logic                                Sign_z_DO,
//    output logic                                Inf_a_SO, Inf_b_SO,
//    output logic                                Zero_a_SO, Zero_b_SO,
//    output logic                                NaN_a_SO, NaN_b_SO, SNaN_SO
//   );

//   // 1. Calculate Pipeline Latency
//   localparam int FRAC_BITS = MAN_BITS + GUARD_BITS; 
  
//   function int calc_needed_stages(int start_bits);
//         int bits;
//         int stages;
//         bits = start_bits;
//         stages = 0;
//         while (bits < FRAC_BITS) begin
//             bits = bits * 2;
//             stages = stages + 1;
//         end
//         return stages; 
//   endfunction

//   localparam int PIPELINE_DEPTH = calc_needed_stages(ROM_ADDR_BITS);

//   // 2. Input Alignment
//   logic start_dly_q;
//   always_ff @(posedge clk or negedge Rst_RBI) begin
//       if (!Rst_RBI) start_dly_q <= 1'b0;
//       else if (Kill_SI) start_dly_q <= 1'b0;
//       else start_dly_q <= Div_start_SI;
//   end

//   // 3. Instantiate Goldschmidt Core
//   logic valid_out;

//   fp_div_Goldschmidt #(
//       .FpFormat     (FpFormat),
//       .GUARD_BITS   (GUARD_BITS),
//       .ROM_ADDR_BITS(ROM_ADDR_BITS)
//   ) goldschmidt_core (
//       .clk            (clk),
//       .rst_ni         (Rst_RBI),
//       .kill_i         (Kill_SI),
//       .start_i        (start_dly_q), 
//       .mant_a_i       (Mant_a_DI),
//       .mant_b_i       (Mant_b_DI),
//       .exp_a_i        (Exp_a_DI),
//       .exp_b_i        (Exp_b_DI),
//       .sign_z_i       (Sign_z_SI),
//       .inf_a_i        (Inf_a_SI), .inf_b_i (Inf_b_SI),
//       .zero_a_i       (Zero_a_SI), .zero_b_i (Zero_b_SI),
//       .nan_a_i        (NaN_a_SI), .nan_b_i (NaN_b_SI), .snan_i (SNaN_SI),
//       .valid_o        (valid_out),
//       .mant_res_o     (Mant_z_DO),
//       .exp_res_o      (Exp_z_DO),
//       .sign_z_o       (Sign_z_DO),
//       .inf_a_o        (Inf_a_SO), .inf_b_o (Inf_b_SO),
//       .zero_a_o       (Zero_a_SO), .zero_b_o (Zero_b_SO),
//       .nan_a_o        (NaN_a_SO), .nan_b_o (NaN_b_SO), .snan_o (SNaN_SO)
//   );

//   // 4. Operand Delay Line (Shift Register)
//   // [FIXED] Delay = 1 (Init Stage) + PIPELINE_DEPTH
//   // Mant_a_DI is already delayed 1 cycle by Preprocess, so it aligns with start_dly_q.
//   localparam int TOTAL_DELAY = PIPELINE_DEPTH + 1;
  
//   typedef struct packed {
//       logic [MAN_BITS:0] a;
//       logic [MAN_BITS:0] b;
//   } operands_t;

//   operands_t pipe_regs [0:TOTAL_DELAY-1];

//   always_ff @(posedge clk or negedge Rst_RBI) begin
//       if (!Rst_RBI) begin
//           for (int i=0; i<TOTAL_DELAY; i++) pipe_regs[i] <= '0;
//       end else begin
//           pipe_regs[0].a <= Mant_a_DI;
//           pipe_regs[0].b <= Mant_b_DI;
//           for (int i=1; i<TOTAL_DELAY; i++) begin
//               pipe_regs[i] <= pipe_regs[i-1];
//           end
//       end
//   end

//   // 5. Output Mapping
//   assign Ready_SO       = 1'b1; 
//   assign Done_SO        = valid_out;
//   assign Div_enable_SO  = valid_out; 
  
//   assign Mant_a_pipe_DO = pipe_regs[TOTAL_DELAY-1].a;
//   assign Mant_b_pipe_DO = pipe_regs[TOTAL_DELAY-1].b;

// endmodule

