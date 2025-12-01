// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Company:        IIS @ ETHZ - Federal Institute of Technology               //
//                                                                            //
// Engineers:      Lei Li                    lile@iis.ee.ethz.ch              //
//                                                                            //
// Additional contributions by:                                               //
//                                                                            //
//                                                                            //
//                                                                            //
// Create Date:    04/03/2018                                                 //
// Design Name:    FPU                                                        //
// Module Name:    control_mvp.sv                                             //
// Project Name:   Private FPU                                                //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    the control logic  of div and sqrt                         //
//                                                                            //
// Revision Date:  12/04/2018                                                 //
//                 Lei Li                                                     //
//                 To address some requirements by Stefan and add low power   //
//                 control for special cases                                  //
// Revision Date:  13/04/2018                                                 //
//                 Lei Li                                                     //
//                 To fix some bug found in Control FSM                       //
//                 when Iteration_unit_num_S  = 2'b10                         //
//                                                                            //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

import defs_div_sqrt_mvp::*;

module control_mvp # (
  parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
  parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, // Full precision as default
   
  parameter logic [2:0] Iteration_unit_num_S  = 3'b011, //Default 4 (encoded in 3 bits)

  parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
  parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
  parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)

)

  (//Input
   input logic                                        Clk_CI,
   input logic                                        Rst_RBI,
   input logic                                        Div_start_SI ,
  //  input logic                                        Sqrt_start_SI,
   input logic                                        Start_SI,
   input logic                                        Kill_SI,
   input logic                                        Special_case_SBI,
   input logic                                        Special_case_dly_SBI,
  //  input logic [C_PC-1:0]                             Precision_ctl_SI,
  //  input logic [1:0]                                  Format_sel_SI,
  //  input logic [C_MANT_FP64:0]                        Numerator_DI,
  //  input logic [C_EXP_FP64:0]                         Exp_num_DI,
  //  input logic [C_MANT_FP64:0]                        Denominator_DI,
  //  input logic [C_EXP_FP64:0]                         Exp_den_DI,
   input logic [MAN_BITS:0]                           Numerator_DI,
   input logic [EXP_BITS:0]                           Exp_num_DI, //exponent of numerator
   input logic [MAN_BITS:0]                           Denominator_DI, 
   input logic [EXP_BITS:0]                           Exp_den_DI, // exponent of denominator


   output logic                                       Div_start_dly_SO ,
  //  output logic                                       Sqrt_start_dly_SO,
   output logic                                       Div_enable_SO,
  //  output logic                                       Sqrt_enable_SO,


   //To next stage
  //  output logic                                       Full_precision_SO,
  //  output logic                                       FP32_SO,
  //  output logic                                       FP64_SO,
  //  output logic                                       FP16_SO,
  //  output logic                                       FP16ALT_SO,

   output logic                                       Ready_SO,
   output logic                                       Done_SO,

  //  output logic [C_MANT_FP64+4:0]                     Mant_result_prenorm_DO
   output logic [MAN_BITS+4:0]                            Mant_result_prenorm_DO,
 //  output logic [3:0]                                 Round_bit_DO,
   output logic [EXP_BITS+1:0]                           Exp_result_prenorm_DO
 );





  //  logic  [C_MANT_FP64+1+4:0]                         Partial_remainder_DN,Partial_remainder_DP; //58bits,r=q+2
  //  logic  [C_MANT_FP64+4:0]                           Quotient_DP; //57bits
   logic  [MAN_BITS+1+4:0]                         Partial_remainder_DN,Partial_remainder_DP; //58bits,r=q+2
  //  logic  [MAN_BITS+4:0]                           Quotient_DP; //57bits
  logic  [MAN_BITS+12:0]                           Quotient_DP; //65bits -> for 8 iteration units


   /////////////////////////////////////////////////////////////////////////////
   // Assign Inputs                                                          //
   /////////////////////////////////////////////////////////////////////////////
  //  logic [C_MANT_FP64+1:0]                            Numerator_se_D;  //sign extension and hidden bit
  //  logic [C_MANT_FP64+1:0]                            Denominator_se_D; //signa extension and hidden bit
  //  logic [C_MANT_FP64+1:0]                            Denominator_se_DB;  //1's complement

   logic [MAN_BITS+1:0]                            Numerator_se_D;  //sign extension and hidden bit TODO check if these values can not be parameters
   logic [MAN_BITS+1:0]                            Denominator_se_D; //signa extension and hidden bit
   logic [MAN_BITS+1:0]                            Denominator_se_DB;  //1's complement

   assign  Numerator_se_D={1'b0,Numerator_DI};

   assign  Denominator_se_D={1'b0,Denominator_DI}; //Sign extended denominator 

  // always_comb
  //  begin
  //    if(FP32_SO)
  //      begin
  //        Denominator_se_DB={~Denominator_se_D[C_MANT_FP64+1:C_MANT_FP64-C_MANT_FP32], {(C_MANT_FP64-C_MANT_FP32){1'b0}} }; //Take the bits of fp32 and invert them, then pad with zeros
  //      end
  //    else if(FP64_SO) begin
  //        Denominator_se_DB=~Denominator_se_D; // Just invert all the 64 bits
  //    end
  //    else if(FP16_SO) begin
  //        Denominator_se_DB={~Denominator_se_D[C_MANT_FP64+1:C_MANT_FP64-C_MANT_FP16], {(C_MANT_FP64-C_MANT_FP16){1'b0}} };
  //    end
  //    else begin
  //        Denominator_se_DB={~Denominator_se_D[C_MANT_FP64+1:C_MANT_FP64-C_MANT_FP16ALT], {(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} };
  //    end
  //  end


  //  generate
  //   if (FpFormat == fpnew_pkg_snax::FP32) begin : gen_fp32
  //     assign Denominator_se_DB = ~Denominator_se_D; // Take invers for 2's complement substraction
  //   end else if (FpFormat == fpnew_pkg_snax::FP64) begin : gen_fp64
  //     assign Denominator_se_DB = ~Denominator_se_D;
  //   end else if (FpFormat == fpnew_pkg_snax::FP16) begin : gen_fp16
  //     assign Denominator_se_DB = ~Denominator_se_D;
  //   end else begin : gen_fp16alt
  //     assign Denominator_se_DB = ~Denominator_se_D;
  //   end
  // endgenerate
   assign Denominator_se_DB = ~Denominator_se_D; // Take invers for 2's complement substraction




  //  logic [C_MANT_FP64+1:0]                            Mant_D_sqrt_Norm;
  //  logic [MAN_BITS+1:0]                            Mant_D_sqrt_Norm; // 

  //  assign Mant_D_sqrt_Norm=Exp_num_DI[0]?{1'b0,Numerator_DI}:{Numerator_DI,1'b0}; //for sqrt

   /////////////////////////////////////////////////////////////////////////////
   // Format Selection      --> No longer needed                                                  //
   /////////////////////////////////////////////////////////////////////////////
  //  logic [1:0]                                      Format_sel_S;

  //  always_ff @(posedge Clk_CI, negedge Rst_RBI)
  //    begin
  //       if(~Rst_RBI)
  //         begin
  //           Format_sel_S<='b0;
  //         end
  //       else if(Start_SI&&Ready_SO)
  //         begin
  //           Format_sel_S<=Format_sel_SI;
  //         end
  //       else
  //         begin
  //           Format_sel_S<=Format_sel_S;
  //         end
  //   end

  //  assign FP32_SO = (Format_sel_S==2'b00);
  //  assign FP64_SO = (Format_sel_S==2'b01);
  //  assign FP16_SO = (Format_sel_S==2'b10);
  //  assign FP16ALT_SO = (Format_sel_S==2'b11);



   /////////////////////////////////////////////////////////////////////////////
   // Precision Control                         //
   /////////////////////////////////////////////////////////////////////////////

  //  logic [C_PC-1:0]                                   Precision_ctl_S;
  //  always_ff @(posedge Clk_CI, negedge Rst_RBI)
  //    begin
  //       if(~Rst_RBI)
  //         begin
  //           Precision_ctl_S<='b0;
  //         end
  //       else if(Start_SI&&Ready_SO)
  //         begin
  //           Precision_ctl_S<=Precision_ctl_SI;
  //         end
  //       else
  //         begin
  //           Precision_ctl_S<=Precision_ctl_S;
  //         end
  //   end
  //  assign Full_precision_SO = (Precision_ctl_S==6'h00);


    //  logic [5:0]                                     State_ctl_S;
  //    logic [5:0]                                     State_Two_iteration_unit_S;
  //    logic [5:0]                                     State_Four_iteration_unit_S;

  //   assign State_Two_iteration_unit_S = Precision_ctl_S[C_PC-1:1];  //Two iteration units
  //   assign State_Four_iteration_unit_S = Precision_ctl_S[C_PC-1:2];  //Four iteration units
    localparam logic Full_precision_SO =                 (PRECISION_CTRL==6'h00);
    localparam logic [5:0] State_Two_iteration_unit_S =  PRECISION_CTRL[C_PC-1:1];  //Two iteration units
    localparam logic [5:0] State_Four_iteration_unit_S = PRECISION_CTRL[C_PC-1:2];  //Four iteration units
    localparam logic [5:0] State_Eight_iteration_unit_S = PRECISION_CTRL[C_PC-1:3]; //Eight iteration units


  logic [5:0]                                     State_ctl_S;
  generate
    //////////////////////one iteration unit, start///////////////////////////////////////
    if (Iteration_unit_num_S == 3'b000) begin 

      if (FpFormat == fpnew_pkg_snax::FP32) begin 
        if (Full_precision_SO) begin
           assign State_ctl_S = 6'h1b; //24+4 more iterations for rounding bits
        end else begin
           assign State_ctl_S = PRECISION_CTRL;
        end 
      end 
      else if (FpFormat == fpnew_pkg_snax::FP64) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h38;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = PRECISION_CTRL;
         end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h0e;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = PRECISION_CTRL;
         end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16ALT) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h0b;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = PRECISION_CTRL;
         end
      end
//////////////////////two iteration units, start///////////////////////////////////////
    end else if (Iteration_unit_num_S == 3'b001) begin

      if (FpFormat == fpnew_pkg_snax::FP32) begin 
        if (Full_precision_SO) begin
           assign State_ctl_S = 6'h0d; //24+4 more iterations for rounding bits
        end else begin
           assign State_ctl_S = State_Two_iteration_unit_S;
        end 
      end 
      else if (FpFormat == fpnew_pkg_snax::FP64) begin
        if(Full_precision_SO) begin
            assign State_ctl_S =  6'h1b;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = State_Two_iteration_unit_S;
         end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h06;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = State_Two_iteration_unit_S;
         end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16ALT) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h05;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = State_Two_iteration_unit_S;
         end
      end
//////////////////////two iteration units, end    ///////////////////////////////////////

//////////////////////three iteration units, start///////////////////////////////////////
    end else if (Iteration_unit_num_S == 3'b010) begin
      if (FpFormat == fpnew_pkg_snax::FP32) begin 
        case(PRECISION_CTRL)
          6'h00:
            begin
              assign State_ctl_S = 6'h08;  //24+3 more iterations for rounding bits
            end
          6'h06,6'h07,6'h08:
            begin
              assign State_ctl_S = 6'h02;
            end
          6'h09,6'h0a,6'h0b:
            begin
              assign State_ctl_S = 6'h03;
            end
          6'h0c,6'h0d,6'h0e:
            begin
              assign State_ctl_S = 6'h04;
            end
          6'h0f,6'h10,6'h11:
            begin
              assign State_ctl_S = 6'h05;
            end
          6'h12,6'h13,6'h14:
            begin
              assign State_ctl_S = 6'h06;
            end
          6'h15,6'h16,6'h17:
            begin
              assign State_ctl_S = 6'h07;
            end
          default:
            begin
              assign State_ctl_S = 6'h08;  //24+3 more iterations for rounding bits
            end
        endcase 
      end
      else if (FpFormat == fpnew_pkg_snax::FP64) begin 
        case(PRECISION_CTRL)
          6'h00:
            begin
              assign State_ctl_S = 6'h12;  //53+4 more iterations for rounding bits
            end
          6'h06,6'h07,6'h08:
            begin
              assign State_ctl_S = 6'h02;
            end
          6'h09,6'h0a,6'h0b:
            begin
              assign State_ctl_S = 6'h03;
            end
          6'h0c,6'h0d,6'h0e:
            begin
              assign State_ctl_S = 6'h04;
            end
          6'h0f,6'h10,6'h11:
            begin
              assign State_ctl_S = 6'h05;
            end
          6'h12,6'h13,6'h14:
            begin
              assign State_ctl_S = 6'h06;
            end
          6'h15,6'h16,6'h17:
            begin
              assign State_ctl_S = 6'h07;
            end
          6'h18,6'h19,6'h1a:
            begin
              assign State_ctl_S = 6'h08;
            end
          6'h1b,6'h1c,6'h1d:
            begin
              assign State_ctl_S = 6'h09;
            end
          6'h1e,6'h1f,6'h20:
            begin
              assign State_ctl_S = 6'h0a;
            end
          6'h21,6'h22,6'h23:
            begin
              assign State_ctl_S = 6'h0b;
            end
          6'h24,6'h25,6'h26:
            begin
              assign State_ctl_S = 6'h0c;
            end
          6'h27,6'h28,6'h29:
            begin
              assign State_ctl_S = 6'h0d;
            end
          6'h2a,6'h2b,6'h2c:
            begin
              assign State_ctl_S = 6'h0e;
            end
          6'h2d,6'h2e,6'h2f:
            begin
              assign State_ctl_S = 6'h0f;
            end
          6'h30,6'h31,6'h32:
            begin
              assign State_ctl_S = 6'h10;
            end
          6'h33,6'h34,6'h35:
            begin
              assign State_ctl_S = 6'h11;
            end
          default:
            begin
              assign State_ctl_S = 6'h12;  //53+4 more iterations for rounding bits
            end
          endcase
        end
        else if (FpFormat == fpnew_pkg_snax::FP16) begin 
          case(PRECISION_CTRL)
            6'h00:
              begin
                assign State_ctl_S = 6'h04;  //12+3 more iterations for rounding bits
              end
            6'h06,6'h07,6'h08:
              begin
                assign State_ctl_S = 6'h02;
              end
            6'h09,6'h0a,6'h0b:
              begin
                assign State_ctl_S = 6'h03;
              end
            default:
              begin
                assign State_ctl_S = 6'h04;  //12+3 more iterations for rounding bits
              end
          endcase
        end
        else if (FpFormat == fpnew_pkg_snax::FP16ALT) begin 
          case(PRECISION_CTRL)
            6'h00:
              begin
                assign State_ctl_S = 6'h03;  //8+4 more iterations for rounding bits
              end
            6'h06,6'h07,6'h08:
              begin
                assign State_ctl_S = 6'h02;
              end
            default:
              begin
                assign State_ctl_S = 6'h03;  //8+4 more iterations for rounding bits
              end
          endcase
        end
//////////////////////three iteration units, end///////////////////////////////////////


//////////////////////four iteration units, start///////////////////////////////////////
    end else if (Iteration_unit_num_S == 3'b011) begin
      
      if (FpFormat == fpnew_pkg_snax::FP32) begin 
        if (Full_precision_SO) begin
           assign State_ctl_S = 6'h06; //24+4 more iterations for rounding bits
        end else begin
           assign State_ctl_S = State_Four_iteration_unit_S;
        end 
      end 
      else if (FpFormat == fpnew_pkg_snax::FP64) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h0d;  //53+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = State_Four_iteration_unit_S;
         end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h03;  //11+4 more iterations for rounding bits
         end else begin
            assign State_ctl_S = State_Four_iteration_unit_S;
         end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16ALT) begin
        if(Full_precision_SO) begin
            assign State_ctl_S = 6'h02;  
         end else begin
            assign State_ctl_S = State_Four_iteration_unit_S;
         end
      end
    end 
    ////////////////////eight iteration units, start///////////////////////////////////////
    else if (Iteration_unit_num_S == 3'b111) begin
      if (FpFormat == fpnew_pkg_snax::FP32) begin
        if (Full_precision_SO) begin
          assign State_ctl_S = 6'h03; // approx 24/8 = 3 cycles
        end else begin
          assign State_ctl_S = State_Eight_iteration_unit_S;
        end
      end
      else if (FpFormat == fpnew_pkg_snax::FP64) begin
        if (Full_precision_SO) begin
          assign State_ctl_S = 6'h07; // approx 56/8 = 7 cycles
        end else begin
          assign State_ctl_S = State_Eight_iteration_unit_S;
        end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16) begin
        if (Full_precision_SO) begin
          assign State_ctl_S = 6'h02;
        end else begin
          assign State_ctl_S = State_Eight_iteration_unit_S;
        end
      end
      else if (FpFormat == fpnew_pkg_snax::FP16ALT) begin
        if (Full_precision_SO) begin
          assign State_ctl_S = 6'h01;
        end else begin
          assign State_ctl_S = State_Eight_iteration_unit_S;
        end
      end
    end
endgenerate
//////////////////////four iteration units, end///////////////////////////////////////




   /////////////////////////////////////////////////////////////////////////////
   // control logic                                                           //
   /////////////////////////////////////////////////////////////////////////////

   logic                                               Div_start_dly_S;

   always_ff @(posedge Clk_CI, negedge Rst_RBI)   //  generate Div_start_dly_S signal
     begin
        if(~Rst_RBI)
          begin
            Div_start_dly_S<=1'b0;
          end
        else if(Div_start_SI&&Ready_SO)
         begin
           Div_start_dly_S<=1'b1;
         end
        else
          begin
            Div_start_dly_S<=1'b0;
          end
    end

   assign Div_start_dly_SO=Div_start_dly_S;

  always_ff @(posedge Clk_CI, negedge Rst_RBI) begin  //  generate Div_enable_SO signal
    if(~Rst_RBI)
      Div_enable_SO<=1'b0;
    // Synchronous reset with Flush
    else if (Kill_SI)
      Div_enable_SO <= 1'b0;
    else if(Div_start_SI&&Ready_SO)
      Div_enable_SO<=1'b1;
    else if(Done_SO)
      Div_enable_SO<=1'b0;
    else
      Div_enable_SO<=Div_enable_SO;
  end

  //  logic                                                Sqrt_start_dly_S;

  //  always_ff @(posedge Clk_CI, negedge Rst_RBI)   //  generate Sqrt_start_dly_SI signal
  //    begin
  //       if(~Rst_RBI)
  //         begin
  //           Sqrt_start_dly_S<=1'b0;
  //         end
  //       else if(Sqrt_start_SI&&Ready_SO)
  //        begin
  //          Sqrt_start_dly_S<=1'b1;
  //        end
  //       else
  //         begin
  //           Sqrt_start_dly_S<=1'b0;
  //         end
  //     end
  //   assign Sqrt_start_dly_SO=Sqrt_start_dly_S;

  //  always_ff @(posedge Clk_CI, negedge Rst_RBI) begin   //  generate Sqrt_enable_SO signal
  //   if(~Rst_RBI)
  //     Sqrt_enable_SO<=1'b0;
  //   else if (Kill_SI)
  //     Sqrt_enable_SO <= 1'b0;
  //   else if(Sqrt_start_SI&&Ready_SO)
  //     Sqrt_enable_SO<=1'b1;
  //   else if(Done_SO)
  //     Sqrt_enable_SO<=1'b0;
  //   else
  //     Sqrt_enable_SO<=Sqrt_enable_SO;
  // end

   logic [5:0]                                                  Crtl_cnt_S;
   logic                                                        Start_dly_S;

  //  assign   Start_dly_S=Div_start_dly_S |Sqrt_start_dly_S;
  assign   Start_dly_S=Div_start_dly_S;

   logic       Fsm_enable_S;
   assign      Fsm_enable_S=( (Start_dly_S | (| Crtl_cnt_S)) && (~Kill_SI) && Special_case_dly_SBI);

   logic                                                        Final_state_S;
   assign     Final_state_S= (Crtl_cnt_S==State_ctl_S);


   always_ff @(posedge Clk_CI, negedge Rst_RBI) //control_FSM
     begin
        if (~Rst_RBI)
          begin
             Crtl_cnt_S     <= '0;
          end
          else if (Final_state_S | Kill_SI)
            begin
              Crtl_cnt_S    <= '0;
            end
          else if(Fsm_enable_S) // one cycle Start_SI
            begin
              Crtl_cnt_S    <= Crtl_cnt_S+1;
            end
          else
            begin
              Crtl_cnt_S    <= '0;
            end
     end // always_ff



    always_ff @(posedge Clk_CI, negedge Rst_RBI) //Generate  Done_SO,  they can share this Done_SO.
      begin
        if(~Rst_RBI)
          begin
            Done_SO<=1'b0;
          end
        else if(Start_SI&&Ready_SO)
          begin
            if(~Special_case_SBI)
              begin
                Done_SO<=1'b1;
              end
            else
              begin
                Done_SO<=1'b0;
              end
          end
        else if(Final_state_S)
          begin
            Done_SO<=1'b1;
          end
        else
          begin
            Done_SO<=1'b0;
          end
       end




   always_ff @(posedge Clk_CI, negedge Rst_RBI) //Generate  Ready_SO
     begin
       if(~Rst_RBI)
         begin
           Ready_SO<=1'b1;
         end

       else if(Start_SI&&Ready_SO)
         begin
            if(~Special_case_SBI)
              begin
                Ready_SO<=1'b1;
              end
            else
              begin
                Ready_SO<=1'b0;
              end
         end
       else if(Final_state_S | Kill_SI)
         begin
           Ready_SO<=1'b1;
         end
       else
         begin
           Ready_SO<=Ready_SO;
         end
     end


  logic  [MAN_BITS+1+4:0]                                      Iteration_cell_a_D [7:0];
  logic  [MAN_BITS+1+4:0]                                      Iteration_cell_b_D [7:0];
  logic  [MAN_BITS+1+4:0]                                      Iteration_cell_a_BMASK_D [7:0];
  logic  [MAN_BITS+1+4:0]                                      Iteration_cell_b_BMASK_D [7:0];
  logic                                                        Iteration_cell_carry_D [7:0];
  logic  [MAN_BITS+1+4:0]                                      Iteration_cell_sum_D [7:0];
  logic  [MAN_BITS+1+4:0]                                      Iteration_cell_sum_AMASK_D [7:0];



  // logic [C_MANT_FP64+5:0]                               Denominator_se_format_DB;  //
  logic [MAN_BITS+5:0]                               Denominator_se_format_DB;  //

  //TODO CHECK 
  // assign Denominator_se_format_DB={Denominator_se_DB[C_MANT_FP64+1:C_MANT_FP64-C_MANT_FP16ALT],
  //                                 {FP16ALT_SO?FP16ALT_SO:Denominator_se_DB[C_MANT_FP64-C_MANT_FP16ALT-1]},
  //                                  Denominator_se_DB[C_MANT_FP64-C_MANT_FP16ALT-2:C_MANT_FP64-C_MANT_FP16],
  //                                  {FP16_SO?FP16_SO:Denominator_se_DB[C_MANT_FP64-C_MANT_FP16-1]},
  //                                  Denominator_se_DB[C_MANT_FP64-C_MANT_FP16-2:C_MANT_FP64-C_MANT_FP32],
  //                                  {FP32_SO?FP32_SO:Denominator_se_DB[C_MANT_FP64-C_MANT_FP32-1]},
  //                                  Denominator_se_DB[C_MANT_FP64-C_MANT_FP32-2:C_MANT_FP64-C_MANT_FP64],
  //                                  FP64_SO,3'b0};
assign Denominator_se_format_DB={Denominator_se_DB,
                                   1'b1,3'b0};


  //                   for           iteration cell_U0
  // logic [C_MANT_FP64+5:0]                           First_iteration_cell_div_a_D,First_iteration_cell_div_b_D;
  logic [MAN_BITS+5:0]                              First_iteration_cell_div_a_D,First_iteration_cell_div_b_D;
  logic                                             Sel_b_for_first_S;


  // assign First_iteration_cell_div_a_D=(Div_start_dly_S)?{Numerator_se_D[C_MANT_FP64+1:C_MANT_FP64-C_MANT_FP16ALT],{FP16ALT_SO?FP16ALT_SO:Numerator_se_D[C_MANT_FP64-C_MANT_FP16ALT-1]},
  //                                                        Numerator_se_D[C_MANT_FP64-C_MANT_FP16ALT-2:C_MANT_FP64-C_MANT_FP16],{FP16_SO?FP16_SO:Numerator_se_D[C_MANT_FP64-C_MANT_FP16-1]},
  //                                                        Numerator_se_D[C_MANT_FP64-C_MANT_FP16-2:C_MANT_FP64-C_MANT_FP32],{FP32_SO?FP32_SO:Numerator_se_D[C_MANT_FP64-C_MANT_FP32-1]},
  //                                                        Numerator_se_D[C_MANT_FP64-C_MANT_FP32-2:C_MANT_FP64-C_MANT_FP64],FP64_SO,3'b0}
  //                                                       :{Partial_remainder_DP[C_MANT_FP64+4:C_MANT_FP64-C_MANT_FP16ALT+3],{FP16ALT_SO?Quotient_DP[0]:Partial_remainder_DP[C_MANT_FP64-C_MANT_FP16ALT+2]},
  //                                                        Partial_remainder_DP[C_MANT_FP64-C_MANT_FP16ALT+1:C_MANT_FP64-C_MANT_FP16+3],{FP16_SO?Quotient_DP[0]:Partial_remainder_DP[C_MANT_FP64-C_MANT_FP16+2]},
  //                                                        Partial_remainder_DP[C_MANT_FP64-C_MANT_FP16+1:C_MANT_FP64-C_MANT_FP32+3],{FP32_SO?Quotient_DP[0]:Partial_remainder_DP[C_MANT_FP64-C_MANT_FP32+2]},
  //                                                        Partial_remainder_DP[C_MANT_FP64-C_MANT_FP32+1:C_MANT_FP64-C_MANT_FP64+3],FP64_SO&&Quotient_DP[0],3'b0};
  assign First_iteration_cell_div_a_D=(Div_start_dly_S)?{Numerator_se_D[MAN_BITS+1:0], 1'b1, 3'b0}
                                                        :{Partial_remainder_DP[MAN_BITS+4:MAN_BITS-MAN_BITS + 3],Quotient_DP[0],3'b0};

  assign Sel_b_for_first_S=(Div_start_dly_S)?1:Quotient_DP[0];
  assign First_iteration_cell_div_b_D=Sel_b_for_first_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
  // assign Iteration_cell_a_BMASK_D[0]=Sqrt_enable_SO?Sqrt_R0:{First_iteration_cell_div_a_D};
  // assign Iteration_cell_b_BMASK_D[0]=Sqrt_enable_SO?Sqrt_Q0:{First_iteration_cell_div_b_D};
  assign Iteration_cell_a_BMASK_D[0]={First_iteration_cell_div_a_D};
  assign Iteration_cell_b_BMASK_D[0]={First_iteration_cell_div_b_D};



  //                   for           iteration cell_U1
  // logic [C_MANT_FP64+5:0]                          Sec_iteration_cell_div_a_D,Sec_iteration_cell_div_b_D;
  logic [MAN_BITS+5:0]                             Sec_iteration_cell_div_a_D,Sec_iteration_cell_div_b_D;
  logic                                            Sel_b_for_sec_S;
  // generate
  //   if(|Iteration_unit_num_S)
  //     begin
  //       assign Sel_b_for_sec_S=~Iteration_cell_sum_AMASK_D[0][C_MANT_FP64+5];
  //       assign Sec_iteration_cell_div_a_D={Iteration_cell_sum_AMASK_D[0][C_MANT_FP64+4:C_MANT_FP64-C_MANT_FP16ALT+3],{FP16ALT_SO?Sel_b_for_sec_S:Iteration_cell_sum_AMASK_D[0][C_MANT_FP64-C_MANT_FP16ALT+2]},
  //                                          Iteration_cell_sum_AMASK_D[0][C_MANT_FP64-C_MANT_FP16ALT+1:C_MANT_FP64-C_MANT_FP16+3],{FP16_SO?Sel_b_for_sec_S:Iteration_cell_sum_AMASK_D[0][C_MANT_FP64-C_MANT_FP16+2]},
  //                                          Iteration_cell_sum_AMASK_D[0][C_MANT_FP64-C_MANT_FP16+1:C_MANT_FP64-C_MANT_FP32+3],{FP32_SO?Sel_b_for_sec_S:Iteration_cell_sum_AMASK_D[0][C_MANT_FP64-C_MANT_FP32+2]},
  //                                          Iteration_cell_sum_AMASK_D[0][C_MANT_FP64-C_MANT_FP32+1:C_MANT_FP64-C_MANT_FP64+3],FP64_SO&&Sel_b_for_sec_S,3'b0};
  //       assign Sec_iteration_cell_div_b_D=Sel_b_for_sec_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
  //       // assign Iteration_cell_a_BMASK_D[1]=Sqrt_enable_SO?Sqrt_R1:{Sec_iteration_cell_div_a_D};
  //       // assign Iteration_cell_b_BMASK_D[1]=Sqrt_enable_SO?Sqrt_Q1:{Sec_iteration_cell_div_b_D};
  //       assign Iteration_cell_a_BMASK_D[1]={Sec_iteration_cell_div_a_D};
  //       assign Iteration_cell_b_BMASK_D[1]={Sec_iteration_cell_div_b_D};
  //     end
  //   endgenerate
  generate
    if(|Iteration_unit_num_S)
      begin
        assign Sel_b_for_sec_S=~Iteration_cell_sum_AMASK_D[0][MAN_BITS+5];
        assign Sec_iteration_cell_div_a_D={Iteration_cell_sum_AMASK_D[0][MAN_BITS+4:MAN_BITS-MAN_BITS + 3],Sel_b_for_sec_S,3'b0};
        assign Sec_iteration_cell_div_b_D=Sel_b_for_sec_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[1]={Sec_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[1]={Sec_iteration_cell_div_b_D};
      end
    endgenerate

  //                   for           iteration cell_U2
  // logic [C_MANT_FP64+5:0]                          Thi_iteration_cell_div_a_D,Thi_iteration_cell_div_b_D;
  logic [MAN_BITS+5:0]                          Thi_iteration_cell_div_a_D,Thi_iteration_cell_div_b_D;
  logic                                            Sel_b_for_thi_S;
  // generate
  //   if((Iteration_unit_num_S==2'b10) | (Iteration_unit_num_S==2'b11))
  //     begin
  //       assign Sel_b_for_thi_S=~Iteration_cell_sum_AMASK_D[1][C_MANT_FP64+5];
  //       assign Thi_iteration_cell_div_a_D={Iteration_cell_sum_AMASK_D[1][C_MANT_FP64+4:C_MANT_FP64-C_MANT_FP16ALT+3],{FP16ALT_SO?Sel_b_for_thi_S:Iteration_cell_sum_AMASK_D[1][C_MANT_FP64-C_MANT_FP16ALT+2]},
  //                                          Iteration_cell_sum_AMASK_D[1][C_MANT_FP64-C_MANT_FP16ALT+1:C_MANT_FP64-C_MANT_FP16+3],{FP16_SO?Sel_b_for_thi_S:Iteration_cell_sum_AMASK_D[1][C_MANT_FP64-C_MANT_FP16+2]},
  //                                          Iteration_cell_sum_AMASK_D[1][C_MANT_FP64-C_MANT_FP16+1:C_MANT_FP64-C_MANT_FP32+3],{FP32_SO?Sel_b_for_thi_S:Iteration_cell_sum_AMASK_D[1][C_MANT_FP64-C_MANT_FP32+2]},
  //                                          Iteration_cell_sum_AMASK_D[1][C_MANT_FP64-C_MANT_FP32+1:C_MANT_FP64-C_MANT_FP64+3],FP64_SO&&Sel_b_for_thi_S,3'b0};
  //       assign Thi_iteration_cell_div_b_D=Sel_b_for_thi_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
  //       // assign Iteration_cell_a_BMASK_D[2]=Sqrt_enable_SO?Sqrt_R2:{Thi_iteration_cell_div_a_D};
  //       // assign Iteration_cell_b_BMASK_D[2]=Sqrt_enable_SO?Sqrt_Q2:{Thi_iteration_cell_div_b_D};
  //       assign Iteration_cell_a_BMASK_D[2]={Thi_iteration_cell_div_a_D};
  //       assign Iteration_cell_b_BMASK_D[2]={Thi_iteration_cell_div_b_D};
  //     end
  // endgenerate
  generate
    if((Iteration_unit_num_S==3'b010) | (Iteration_unit_num_S==3'b011) | (Iteration_unit_num_S==3'b111))
      begin
        assign Sel_b_for_thi_S=~Iteration_cell_sum_AMASK_D[1][MAN_BITS+5];
        assign Thi_iteration_cell_div_a_D={Iteration_cell_sum_AMASK_D[1][MAN_BITS+4:MAN_BITS-MAN_BITS+3],Sel_b_for_thi_S,3'b0};
        assign Thi_iteration_cell_div_b_D=Sel_b_for_thi_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[2]={Thi_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[2]={Thi_iteration_cell_div_b_D};
      end
  endgenerate
  //                   for           iteration cell_U3
  // logic [C_MANT_FP64+5:0]                          Fou_iteration_cell_div_a_D,Fou_iteration_cell_div_b_D;
  logic [MAN_BITS+5:0]                          Fou_iteration_cell_div_a_D,Fou_iteration_cell_div_b_D;
  logic                                            Sel_b_for_fou_S;
  // generate
  //   if(Iteration_unit_num_S==2'b11)
  //     begin
  //       assign Sel_b_for_fou_S=~Iteration_cell_sum_AMASK_D[2][C_MANT_FP64+5];
  //       assign Fou_iteration_cell_div_a_D={Iteration_cell_sum_AMASK_D[2][C_MANT_FP64+4:C_MANT_FP64-C_MANT_FP16ALT+3],{FP16ALT_SO?Sel_b_for_fou_S:Iteration_cell_sum_AMASK_D[2][C_MANT_FP64-C_MANT_FP16ALT+2]},
  //                                          Iteration_cell_sum_AMASK_D[2][C_MANT_FP64-C_MANT_FP16ALT+1:C_MANT_FP64-C_MANT_FP16+3],{FP16_SO?Sel_b_for_fou_S:Iteration_cell_sum_AMASK_D[2][C_MANT_FP64-C_MANT_FP16+2]},
  //                                          Iteration_cell_sum_AMASK_D[2][C_MANT_FP64-C_MANT_FP16+1:C_MANT_FP64-C_MANT_FP32+3],{FP32_SO?Sel_b_for_fou_S:Iteration_cell_sum_AMASK_D[2][C_MANT_FP64-C_MANT_FP32+2]},
  //                                          Iteration_cell_sum_AMASK_D[2][C_MANT_FP64-C_MANT_FP32+1:C_MANT_FP64-C_MANT_FP64+3],FP64_SO&&Sel_b_for_fou_S,3'b0};
  //       assign Fou_iteration_cell_div_b_D=Sel_b_for_fou_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
  //       // assign Iteration_cell_a_BMASK_D[3]=Sqrt_enable_SO?Sqrt_R3:{Fou_iteration_cell_div_a_D};
  //       // assign Iteration_cell_b_BMASK_D[3]=Sqrt_enable_SO?Sqrt_Q3:{Fou_iteration_cell_div_b_D};
  //       assign Iteration_cell_a_BMASK_D[3]={Fou_iteration_cell_div_a_D};
  //       assign Iteration_cell_b_BMASK_D[3]={Fou_iteration_cell_div_b_D};
  //     end
  // endgenerate
  generate
    if((Iteration_unit_num_S==3'b011) | (Iteration_unit_num_S==3'b111))
      begin
        assign Sel_b_for_fou_S=~Iteration_cell_sum_AMASK_D[2][MAN_BITS+5];
        assign Fou_iteration_cell_div_a_D={Iteration_cell_sum_AMASK_D[2][MAN_BITS+4:MAN_BITS-MAN_BITS+3],Sel_b_for_fou_S,3'b0};
        assign Fou_iteration_cell_div_b_D=Sel_b_for_fou_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[3]={Fou_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[3]={Fou_iteration_cell_div_b_D};
      end
  endgenerate

  // Additional iteration cells for 8-unit support (U4..U7)
  logic [MAN_BITS+5:0]                          Fiv_iteration_cell_div_a_D,Fiv_iteration_cell_div_b_D;
  logic                                            Sel_b_for_fiv_S;
  logic [MAN_BITS+5:0]                          Six_iteration_cell_div_a_D,Six_iteration_cell_div_b_D;
  logic                                            Sel_b_for_six_S;
  logic [MAN_BITS+5:0]                          Sev_iteration_cell_div_a_D,Sev_iteration_cell_div_b_D;
  logic                                            Sel_b_for_sev_S;
  logic [MAN_BITS+5:0]                          Eig_iteration_cell_div_a_D,Eig_iteration_cell_div_b_D;
  logic                                            Sel_b_for_eig_S;

  generate
    if(Iteration_unit_num_S==3'b111)
      begin
        // U4
        assign Sel_b_for_fiv_S = ~Iteration_cell_sum_AMASK_D[3][MAN_BITS+5];
        assign Fiv_iteration_cell_div_a_D = {Iteration_cell_sum_AMASK_D[3][MAN_BITS+4:MAN_BITS-MAN_BITS+3],Sel_b_for_fiv_S,3'b0};
        assign Fiv_iteration_cell_div_b_D = Sel_b_for_fiv_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[4] = {Fiv_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[4] = {Fiv_iteration_cell_div_b_D};

        // U5
        assign Sel_b_for_six_S = ~Iteration_cell_sum_AMASK_D[4][MAN_BITS+5];
        assign Six_iteration_cell_div_a_D = {Iteration_cell_sum_AMASK_D[4][MAN_BITS+4:MAN_BITS-MAN_BITS+3],Sel_b_for_six_S,3'b0};
        assign Six_iteration_cell_div_b_D = Sel_b_for_six_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[5] = {Six_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[5] = {Six_iteration_cell_div_b_D};

        // U6
        assign Sel_b_for_sev_S = ~Iteration_cell_sum_AMASK_D[5][MAN_BITS+5];
        assign Sev_iteration_cell_div_a_D = {Iteration_cell_sum_AMASK_D[5][MAN_BITS+4:MAN_BITS-MAN_BITS+3],Sel_b_for_sev_S,3'b0};
        assign Sev_iteration_cell_div_b_D = Sel_b_for_sev_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[6] = {Sev_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[6] = {Sev_iteration_cell_div_b_D};

        // U7
        assign Sel_b_for_eig_S = ~Iteration_cell_sum_AMASK_D[6][MAN_BITS+5];
        assign Eig_iteration_cell_div_a_D = {Iteration_cell_sum_AMASK_D[6][MAN_BITS+4:MAN_BITS-MAN_BITS+3],Sel_b_for_eig_S,3'b0};
        assign Eig_iteration_cell_div_b_D = Sel_b_for_eig_S?Denominator_se_format_DB:{Denominator_se_D,4'b0};
        assign Iteration_cell_a_BMASK_D[7] = {Eig_iteration_cell_div_a_D};
        assign Iteration_cell_b_BMASK_D[7] = {Eig_iteration_cell_div_b_D};
      end
  endgenerate

   /////////////////////////////////////////////////////////////////////////////
   // Masking Contrl                                                          //
   /////////////////////////////////////////////////////////////////////////////


  // logic [C_MANT_FP64+1+4:0]                          Mask_bits_ctl_S;  //For extension
  // logic [MAN_BITS+1+4:0]                          Mask_bits_ctl_S;  //For extension

  // assign Mask_bits_ctl_S =58'h3ff_ffff_ffff_ffff;   //It is not needed. The corresponding process is handled the above codes

   /////////////////////////////////////////////////////////////////////////////
   // Iteration Instances  with masking control                               //
   /////////////////////////////////////////////////////////////////////////////


  logic                                             Div_enable_SI   [7:0];
  logic                                             Div_start_dly_SI   [7:0];
  logic                                             Sqrt_enable_SI   [7:0];
  generate
    genvar i,j;
      for (i=0; i <= Iteration_unit_num_S ; i++) //Depending on how many iteration units you make inparallel
        begin
          // for (j = 0; j <= C_MANT_FP64+5; j++) begin
          //     assign Iteration_cell_a_D[i][j] = Mask_bits_ctl_S[j] && Iteration_cell_a_BMASK_D[i][j];
          //     assign Iteration_cell_b_D[i][j] = Mask_bits_ctl_S[j] && Iteration_cell_b_BMASK_D[i][j];
          //     assign Iteration_cell_sum_AMASK_D[i][j] = Mask_bits_ctl_S[j] && Iteration_cell_sum_D[i][j];
          // end
          for (j = 0; j <= MAN_BITS+5; j++) begin
              assign Iteration_cell_a_D[i][j] = Iteration_cell_a_BMASK_D[i][j];
              assign Iteration_cell_b_D[i][j] = Iteration_cell_b_BMASK_D[i][j];
              assign Iteration_cell_sum_AMASK_D[i][j] = Iteration_cell_sum_D[i][j];
          end

          assign  Div_enable_SI[i] = Div_enable_SO;
          assign  Div_start_dly_SI[i] = Div_start_dly_S;
          // assign  Sqrt_enable_SI[i] = Sqrt_enable_SO;
          iteration_div_sqrt_mvp #(MAN_BITS+6) iteration_div_sqrt
          (
          .A_DI                                    (Iteration_cell_a_D[i]            ),
          .B_DI                                    (Iteration_cell_b_D[i]            ),
          // .Div_enable_SI                           (Div_enable_SI[i]                 ),
          // .Div_start_dly_SI                        (Div_start_dly_SI[i]              ),
          // .Sqrt_enable_SI                          (Sqrt_enable_SI[i]                ),
          // .D_DI                                    (Sqrt_DI[i]                       ),
          // .D_DO                                    (Sqrt_DO[i]                       ),
          .Sum_DO                                  (Iteration_cell_sum_D[i]          ),
          .Carry_out_DO                            (Iteration_cell_carry_D[i]        )
         );

        end

  endgenerate



  always_comb
    begin
      case (Iteration_unit_num_S)
        3'b000:
          begin
            if(Fsm_enable_S)
              //  Partial_remainder_DN = Sqrt_enable_SO?Sqrt_R1:Iteration_cell_sum_AMASK_D[0];
              Partial_remainder_DN = Iteration_cell_sum_AMASK_D[0];
            else
               Partial_remainder_DN = Partial_remainder_DP;
          end
        3'b001:
          begin
            if(Fsm_enable_S)
              //  Partial_remainder_DN = Sqrt_enable_SO?Sqrt_R2:Iteration_cell_sum_AMASK_D[1];
              Partial_remainder_DN = Iteration_cell_sum_AMASK_D[1];
            else
               Partial_remainder_DN = Partial_remainder_DP;
          end
        3'b010:
          begin
            if(Fsm_enable_S)
              //  Partial_remainder_DN = Sqrt_enable_SO?Sqrt_R3:Iteration_cell_sum_AMASK_D[2];
              Partial_remainder_DN = Iteration_cell_sum_AMASK_D[2];
            else
               Partial_remainder_DN = Partial_remainder_DP;
          end
        3'b011:
          begin
            if(Fsm_enable_S)
              //  Partial_remainder_DN = Sqrt_enable_SO?Sqrt_R4:Iteration_cell_sum_AMASK_D[3];
              Partial_remainder_DN = Iteration_cell_sum_AMASK_D[3];
            else
               Partial_remainder_DN = Partial_remainder_DP;
          end
        3'b111:
          begin
            if(Fsm_enable_S)
              Partial_remainder_DN = Iteration_cell_sum_AMASK_D[7];
            else
              Partial_remainder_DN = Partial_remainder_DP;
          end
        endcase
     end



   always_ff @(posedge Clk_CI, negedge Rst_RBI)   // partial_remainder
     begin
        if(~Rst_RBI)
          begin
             Partial_remainder_DP <= '0;
          end
        else
          begin
             Partial_remainder_DP <= Partial_remainder_DN;
          end
    end

  //  logic [C_MANT_FP64+4:0] Quotient_DN;
  // logic [MAN_BITS+4:0] Quotient_DN;
  logic [MAN_BITS+12:0] Quotient_DN;

  always_comb                            // Can choosen the different carry-outs based on different operations
    begin
      case (Iteration_unit_num_S)
        3'b000:
          begin
            if(Fsm_enable_S)
              //  Quotient_DN= Sqrt_enable_SO ? {Quotient_DP[C_MANT_FP64+3:0],Sqrt_quotinent_S[3]} :{Quotient_DP[C_MANT_FP64+3:0],Iteration_cell_carry_D[0]};
              Quotient_DN= {Quotient_DP[MAN_BITS+3:0],Iteration_cell_carry_D[0]};
            else
               Quotient_DN= Quotient_DP;
          end
        3'b001:
          begin
            if(Fsm_enable_S)
              //  Quotient_DN= Sqrt_enable_SO ? {Quotient_DP[C_MANT_FP64+2:0],Sqrt_quotinent_S[3:2]} :{Quotient_DP[C_MANT_FP64+2:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1]};
              Quotient_DN= {Quotient_DP[MAN_BITS+2:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1]};
            else
               Quotient_DN= Quotient_DP;
          end
        3'b010:
          begin
            if(Fsm_enable_S)
              //  Quotient_DN= Sqrt_enable_SO ? {Quotient_DP[C_MANT_FP64+1:0],Sqrt_quotinent_S[3:1]} : {Quotient_DP[C_MANT_FP64+1:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1],Iteration_cell_carry_D[2]};
              Quotient_DN= {Quotient_DP[MAN_BITS+1:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1],Iteration_cell_carry_D[2]};
            else
               Quotient_DN= Quotient_DP;
          end
        3'b011:
          begin
            if(Fsm_enable_S)
              //  Quotient_DN= Sqrt_enable_SO ? {Quotient_DP[C_MANT_FP64:0],Sqrt_quotinent_S } : {Quotient_DP[C_MANT_FP64:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1],Iteration_cell_carry_D[2],Iteration_cell_carry_D[3]};
              Quotient_DN= {Quotient_DP[MAN_BITS:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1],Iteration_cell_carry_D[2],Iteration_cell_carry_D[3]};
            else
               Quotient_DN= Quotient_DP;
          end
        3'b111:
          begin
            if(Fsm_enable_S)
              Quotient_DN= {Quotient_DP[MAN_BITS+4:0],Iteration_cell_carry_D[0],Iteration_cell_carry_D[1],Iteration_cell_carry_D[2],Iteration_cell_carry_D[3],Iteration_cell_carry_D[4],Iteration_cell_carry_D[5],Iteration_cell_carry_D[6],Iteration_cell_carry_D[7]};
            else
              Quotient_DN= Quotient_DP;
          end
        endcase
     end

   always_ff @(posedge Clk_CI, negedge Rst_RBI)   // Quotient
     begin
        if(~Rst_RBI)
          begin
          Quotient_DP <= '0;
          end
        else
          Quotient_DP <= Quotient_DN;
    end


   /////////////////////////////////////////////////////////////////////////////
   // Precision Control for outputs                                          //
   /////////////////////////////////////////////////////////////////////////////

 
//////////////////////one iteration unit, start///////////////////////////////////////
   generate
    if(Iteration_unit_num_S==3'b000)
       begin
        // always_comb
          // begin
            // case (Format_sel_S)
              // 2'b00:
        if (FpFormat == fpnew_pkg_snax::FP32) 
                begin
                  always_comb
                    begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h17:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32:0],{(C_MANT_FP64-C_MANT_FP32+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h16:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-1:0],{(C_MANT_FP64-C_MANT_FP32+4+1){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(4+1){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h15:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-2:0],{(C_MANT_FP64-C_MANT_FP32+4+2){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-2:0],{(4+2){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-3:0],{(C_MANT_FP64-C_MANT_FP32+4+3){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-3:0],{(4+3){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h13:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-4:0],{(C_MANT_FP64-C_MANT_FP32+4+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-4:0],{(4+4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h12:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-5:0],{(C_MANT_FP64-C_MANT_FP32+4+5){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-5:0],{(4+5){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h11:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-6:0],{(C_MANT_FP64-C_MANT_FP32+4+6){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-6:0],{(4+6){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-7:0],{(C_MANT_FP64-C_MANT_FP32+4+7){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-7:0],{(4+7){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0f:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-8:0],{(C_MANT_FP64-C_MANT_FP32+4+8){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-8:0],{(4+8){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-9:0],{(C_MANT_FP64-C_MANT_FP32+4+9){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-9:0],{(4+9){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0d:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-10:0],{(C_MANT_FP64-C_MANT_FP32+4+10){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-10:0],{(4+10){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-11:0],{(C_MANT_FP64-C_MANT_FP32+4+11){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-11:0],{(4+11){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0b:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-12:0],{(C_MANT_FP64-C_MANT_FP32+4+12){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-12:0],{(4+12){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-13:0],{(C_MANT_FP64-C_MANT_FP32+4+13){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-13:0],{(4+13){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h09:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-14:0],{(C_MANT_FP64-C_MANT_FP32+4+14){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-14:0],{(4+14){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-15:0],{(C_MANT_FP64-C_MANT_FP32+4+15){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-15:0],{(4+15){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-16:0],{(C_MANT_FP64-C_MANT_FP32+4+16){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-16:0],{(4+16){1'b1}}}; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                    end
                end

              // 2'b01:
        else if (FpFormat == fpnew_pkg_snax::FP64)
                begin
                  always_comb
                    begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = Quotient_DP[C_MANT_FP64+4:0]; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h34:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64:0],{(4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h33:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-1:0],{(4+1){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(4+1){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h32:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-2:0],{(4+2){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-2:0],{(4+2){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h31:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-3:0],{(4+3){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-3:0],{(4+3){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h30:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-4:0],{(4+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-4:0],{(4+4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h2f:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-5:0],{(4+5){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-5:0],{(4+5){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h2e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-6:0],{(4+6){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-6:0],{(4+6){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h2d:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-7:0],{(4+7){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-7:0],{(4+7){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h2c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-8:0],{(4+8){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-8:0],{(4+8){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h2b:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-9:0],{(4+9){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-9:0],{(4+9){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h2a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-10:0],{(4+10){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-10:0],{(4+10){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h29:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-11:0],{(4+11){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-11:0],{(4+11){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h28:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-12:0],{(4+12){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-12:0],{(4+12){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h27:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-13:0],{(4+13){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-13:0],{(4+13){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h26:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-14:0],{(4+14){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-14:0],{(4+14){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h25:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-15:0],{(4+15){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-15:0],{(4+15){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h24:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-16:0],{(4+16){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-16:0],{(4+16){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h23:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-17:0],{(4+17){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-17:0],{(4+17){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h22:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-18:0],{(4+18){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-18:0],{(4+18){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h21:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-19:0],{(4+19){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-19:0],{(4+19){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h20:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-20:0],{(4+20){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-20:0],{(4+20){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h1f:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-21:0],{(4+21){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-21:0],{(4+21){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h1e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-22:0],{(4+22){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-22:0],{(4+22){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h1d:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-23:0],{(4+23){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-23:0],{(4+23){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h1c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-24:0],{(4+24){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-24:0],{(4+24){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h1b:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-25:0],{(4+25){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-25:0],{(4+25){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h1a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-26:0],{(4+26){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-26:0],{(4+26){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h19:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-27:0],{(4+27){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-27:0],{(4+27){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h18:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-28:0],{(4+28){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-28:0],{(4+28){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h17:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-29:0],{(4+29){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-29:0],{(4+29){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h16:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-30:0],{(4+30){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-30:0],{(4+30){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h15:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-31:0],{(4+31){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-31:0],{(4+31){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-32:0],{(4+32){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-32:0],{(4+32){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h13:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-33:0],{(4+33){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-33:0],{(4+33){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h12:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-34:0],{(4+34){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-34:0],{(4+34){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h11:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-35:0],{(4+35){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-35:0],{(4+35){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-36:0],{(4+36){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-36:0],{(4+36){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0f:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-37:0],{(4+37){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-37:0],{(4+37){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-38:0],{(4+38){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-38:0],{(4+38){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0d:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-39:0],{(4+39){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-39:0],{(4+39){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-40:0],{(4+40){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-40:0],{(4+40){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0b:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-41:0],{(4+41){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-41:0],{(4+41){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-42:0],{(4+42){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-42:0],{(4+42){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h09:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-43:0],{(4+43){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-43:0],{(4+43){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-44:0],{(4+44){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-44:0],{(4+44){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-45:0],{(4+45){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-45:0],{(4+45){1'b1}}}; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = Quotient_DP[C_MANT_FP64+4:0]; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                    end
                end
        else if (FpFormat == fpnew_pkg_snax::FP16)
              // 2'b10:
                begin
                  always_comb
                    begin
                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+4:0],{(C_MANT_FP64-C_MANT_FP16){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h0a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16:0],{(C_MANT_FP64-C_MANT_FP16+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h09:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16-1:0],{(C_MANT_FP64-C_MANT_FP16+4+1){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(4+1){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16-2:0],{(C_MANT_FP64-C_MANT_FP16+4+2){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-2:0],{(4+2){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16-3:0],{(C_MANT_FP64-C_MANT_FP16+4+3){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-3:0],{(4+3){1'b1}}}; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+4:0],{(C_MANT_FP64-C_MANT_FP16){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                    end
                end
        else if (FpFormat == fpnew_pkg_snax::FP16ALT)
              // 2'b11:
                begin
                    always_comb
                    begin
                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT:0],{(C_MANT_FP64-C_MANT_FP16ALT+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                    end
                end
            // endcase
          end
        // end
      endgenerate
//////////////////////one iteration unit, end//////////////////////////////////////////

//////////////////////two iteration units, start///////////////////////////////////////
   generate
    if(Iteration_unit_num_S==3'b001)
       begin
        // always_comb
        //   begin
            // case (FpFormat)
            if (FpFormat == fpnew_pkg_snax::FP32)
              // 2'b00:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h17,6'h16:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32:0],{(C_MANT_FP64-C_MANT_FP32+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h15,6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-2:0],{(C_MANT_FP64-C_MANT_FP32+4+2){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-2:0],{(4+2){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h13,6'h12:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-4:0],{(C_MANT_FP64-C_MANT_FP32+4+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-4:0],{(4+4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h11,6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-6:0],{(C_MANT_FP64-C_MANT_FP32+4+6){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-6:0],{(4+6){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0f,6'h0e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-8:0],{(C_MANT_FP64-C_MANT_FP32+4+8){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-8:0],{(4+8){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-10:0],{(C_MANT_FP64-C_MANT_FP32+4+10){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-10:0],{(4+10){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-12:0],{(C_MANT_FP64-C_MANT_FP32+4+12){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-12:0],{(4+12){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-14:0],{(C_MANT_FP64-C_MANT_FP32+4+14){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-14:0],{(4+14){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-16:0],{(C_MANT_FP64-C_MANT_FP32+4+16){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-16:0],{(4+16){1'b1}}}; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
                end
              else if (FpFormat == fpnew_pkg_snax::FP64)  
              // 2'b01:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],1'b0}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],1'b1}; //+3
                      end
                    6'h34:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+1:1],{(4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+1:1],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h33,6'h32:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-1:0],{(4+1){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(4+1){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h31,6'h30:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-3:0],{(4+3){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-3:0],{(4+3){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2f,6'h2e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-5:0],{(4+5){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-5:0],{(4+5){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2d,6'h2c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-7:0],{(4+7){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-7:0],{(4+7){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2b,6'h2a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-9:0],{(4+9){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-9:0],{(4+9){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h29,6'h28:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-11:0],{(4+11){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-11:0],{(4+11){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h27,6'h26:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-13:0],{(4+13){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-13:0],{(4+13){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h25,6'h24:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-15:0],{(4+15){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-15:0],{(4+15){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h23,6'h22:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-17:0],{(4+17){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-17:0],{(4+17){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h21,6'h20:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-19:0],{(4+19){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-19:0],{(4+19){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1f,6'h1e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-21:0],{(4+21){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-21:0],{(4+21){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1d,6'h1c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-23:0],{(4+23){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-23:0],{(4+23){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1b,6'h1a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-25:0],{(4+25){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-25:0],{(4+25){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h19,6'h18:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-27:0],{(4+27){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-27:0],{(4+27){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h17,6'h16:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-29:0],{(4+29){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-29:0],{(4+29){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h15,6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-31:0],{(4+31){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-31:0],{(4+31){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h13,6'h12:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-33:0],{(4+33){1'b0}} }; //Precision_ctl_S+1Quotient_DP
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-33:0],{(4+33){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h11,6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-35:0],{(4+35){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-35:0],{(4+35){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0f,6'h0e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-37:0],{(4+37){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-37:0],{(4+37){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-39:0],{(4+39){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-39:0],{(4+39){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-41:0],{(4+41){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-41:0],{(4+41){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-43:0],{(4+43){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-43:0],{(4+43){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-45:0],{(4+45){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-45:0],{(4+45){1'b1}} }; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],1'b0}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],1'b1}; //+3
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16)
              // 2'b10:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+3:0],{(C_MANT_FP64-C_MANT_FP16+1){1'b0}} }; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}} }; //+3
                      end
                    6'h0a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+1:1],{(C_MANT_FP64-C_MANT_FP16+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+1:1],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16-1:0],{(C_MANT_FP64-C_MANT_FP16+4+1){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(4+1){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16-3:0],{(C_MANT_FP64-C_MANT_FP16+4+3){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-3:0],{(4+3){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+4:0],{(C_MANT_FP64-C_MANT_FP16){1'b0}} }; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}} }; //+3
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16ALT)
              // 2'b11:
                begin
                  always_comb
                  begin

                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],1'b1}; //+3
                        
                      end
                    6'h07:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT:0],{(C_MANT_FP64-C_MANT_FP16ALT+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],1'b1}; //+3
                      end
                  endcase
                end
                end
            // endcase
          end
      //  end
     endgenerate
//////////////////////two iteration units, end//////////////////////////////////////////

//////////////////////three iteration units, start///////////////////////////////////////
   generate
    if(Iteration_unit_num_S==3'b010)
       begin
        // always_comb
        //   begin
            if (FpFormat == fpnew_pkg_snax::FP32)
            // case (Format_sel_S)
              // 2'b00:
                begin
                  always_comb
                    begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+3:0],{(C_MANT_FP64-C_MANT_FP32+1){1'b0}}}; //+3
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b0}}}; //In original code was adding an additional zero -> gave rounding error
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}}}; //+3
                      end
                    6'h17,6'h16,6'h15:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32:0],{(C_MANT_FP64-C_MANT_FP32+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h14,6'h13,6'h12:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-3:0],{(C_MANT_FP64-C_MANT_FP32+4+3){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-3:0],{(4+3){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h11,6'h10,6'h0f:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-6:0],{(C_MANT_FP64-C_MANT_FP32+4+6){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-6:0],{(4+6){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0e,6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-9:0],{(C_MANT_FP64-C_MANT_FP32+4+9){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-9:0],{(4+9){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a,6'h09:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-12:0],{(C_MANT_FP64-C_MANT_FP32+4+12){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-12:0],{(4+12){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h08,6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-15:0],{(C_MANT_FP64-C_MANT_FP32+4+15){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-15:0],{(4+15){1'b1}}}; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+3:0],{(C_MANT_FP64-C_MANT_FP32+1){1'b0}}}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}}}; //+3
                      end
                  endcase
                end
                end
              else if (FpFormat == fpnew_pkg_snax::FP64)
              // 2'b01:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = Quotient_DP[C_MANT_FP64+4:0]; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h34,6'h33:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+1:1],{(4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+1:1],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h32,6'h31,6'h30:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-2:0],{(4+2){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-2:0],{(4+2){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2f,6'h2e,6'h2d:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-5:0],{(4+5){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-5:0],{(4+5){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2c,6'h2b,6'h2a:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-8:0],{(4+8){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-8:0],{(4+8){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h29,6'h28,6'h27:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-11:0],{(4+11){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-11:0],{(4+11){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h26,6'h25,6'h24:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-14:0],{(4+14){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-14:0],{(4+14){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h23,6'h22,6'h21:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-17:0],{(4+17){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-17:0],{(4+17){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h20,6'h1f,6'h1e:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-20:0],{(4+20){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-20:0],{(4+20){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1d,6'h1c,6'h1b:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-23:0],{(4+23){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-23:0],{(4+23){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1a,6'h19,6'h18:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-26:0],{(4+26){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-26:0],{(4+26){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h17,6'h16,6'h15:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-29:0],{(4+29){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-29:0],{(4+29){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h14,6'h13,6'h12:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-32:0],{(4+32){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-32:0],{(4+32){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h11,6'h10,6'h0f:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-35:0],{(4+35){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-35:0],{(4+35){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0e,6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-38:0],{(4+38){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-38:0],{(4+38){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a,6'h09:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-41:0],{(4+41){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-41:0],{(4+41){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h08,6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-44:0],{(4+44){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-44:0],{(4+44){1'b1}} }; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = Quotient_DP[C_MANT_FP64+4:0]; //+4
                        // Mant_result_prenorm_DO = Quotient_DP[MAN_BITS+4:0]; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16)
              // 2'b10:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+4:0],{(C_MANT_FP64-C_MANT_FP16){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h0a,6'h09:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+1:1],{(C_MANT_FP64-C_MANT_FP16+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+1:1],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h08,6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16-2:0],{(C_MANT_FP64-C_MANT_FP16+4+2){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-2:0],{(4+2){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+4:0],{(C_MANT_FP64-C_MANT_FP16){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16ALT)
              // 2'b11:
                begin
                  always_comb
                  begin

                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0] }; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Mant_result_prenorm_DOQuotient_DP[MAN_BITS+4:0] }; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                        
                      end
                  endcase
                end
                end
            // endcase
          end
        // end
      endgenerate
//////////////////////three iteration units, end//////////////////////////////////////////

//////////////////////four iteration units, start///////////////////////////////////////
   generate
    if(Iteration_unit_num_S==3'b011)
       begin
        
            // case (Format_sel_S)
            if (FpFormat == fpnew_pkg_snax::FP32)
              
              // 2'b00:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h17,6'h16,6'h15,6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32:0],{(C_MANT_FP64-C_MANT_FP32+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h13,6'h12,6'h11,6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-4:0],{(C_MANT_FP64-C_MANT_FP32+4+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-4:0],{(4+4){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0f,6'h0e,6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-8:0],{(C_MANT_FP64-C_MANT_FP32+4+8){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-8:0],{(4+8){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a,6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-12:0],{(C_MANT_FP64-C_MANT_FP32+4+12){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-12:0],{(4+12){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-16:0],{(C_MANT_FP64-C_MANT_FP32+4+16){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-16:0],{(4+16){1'b1}}}; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP64)
              // 2'b01:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],{(1){1'b0}}}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}}}; //+3
                      end
                    6'h34:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],{(1){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h33,6'h32,6'h31,6'h30:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-1:0],{(5){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(5){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2f,6'h2e,6'h2d,6'h2c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-5:0],{(9){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-5:0],{(9){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2b,6'h2a,6'h29,6'h28:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-9:0],{(13){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-9:0],{(13){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h27,6'h26,6'h25,6'h24:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-13:0],{(17){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-13:0],{(17){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h23,6'h22,6'h21,6'h20:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-17:0],{(21){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-17:0],{(21){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1f,6'h1e,6'h1d,6'h1c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-21:0],{(25){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-21:0],{(25){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1b,6'h1a,6'h19,6'h18:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-25:0],{(29){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-25:0],{(29){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h17,6'h16,6'h15,6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-29:0],{(33){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-29:0],{(33){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h13,6'h12,6'h11,6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-33:0],{(37){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-33:0],{(37){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0f,6'h0e,6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-37:0],{(41){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-37:0],{(41){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a,6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-41:0],{(45){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-41:0],{(45){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-45:0],{(49){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-45:0],{(49){1'b1}} }; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],{(1){1'b0}}}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+3:0],{(1){1'b1}}}; //+3
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16)
              // 2'b10:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+5:0],{(C_MANT_FP64-C_MANT_FP16-1){1'b0}} }; //+5
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+5
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h0a,6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+1:1],{(C_MANT_FP64-C_MANT_FP16+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+1:1],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+1-4:0],{(C_MANT_FP64-C_MANT_FP16+4+3){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+1-4:0],{(4+3){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+5:0],{(C_MANT_FP64-C_MANT_FP16-1){1'b0}} }; //+5
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+5
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16ALT) 
              // 2'b11:
                begin
                  always_comb
                  begin

                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT:0],{(C_MANT_FP64-C_MANT_FP16ALT+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
            // endcase
          end
        end
      endgenerate
//////////////////////four iteration units, end///////////////////////////////////////

//////////////////////eight iteration units, start/////////////////////////////////////
generate
    if(Iteration_unit_num_S==3'b111)
       begin
            // case (Format_sel_S)
            if (FpFormat == fpnew_pkg_snax::FP32)
              // 2'b00:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00: //TODO LOOK AT THE PRECISION
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+8:5],1'b1};//,1'b1}; //+4
                      end
                    6'h17,6'h16,6'h15,6'h14,6'h13,6'h12,6'h11,6'h10:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32:0],{(C_MANT_FP64-C_MANT_FP32+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-0:0],{(8){1'b1}}}; //Precision_ctl_S+1
                      end
                    6'h0f,6'h0e,6'h0d,6'h0c,6'h0b,6'h0a,6'h09,6'h08:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-4:0],{(C_MANT_FP64-C_MANT_FP32+4+4){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-8:0],{(8+8){1'b1}}}; //Precision_ctl_S+1
                      end
                    
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32-16:0],{(C_MANT_FP64-C_MANT_FP32+4+16){1'b0}}}; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-16:0],{(4+16){1'b1}}}; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP32+4:0],{(C_MANT_FP64-C_MANT_FP32){1'b0}}}; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+8:7],1'b1}; //+4
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP64)
              // 2'b01:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'h00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],{(1){1'b0}}}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+11:8],{(1){1'b1}}}; //+3
                      end
                    6'h34: //TODO LOOK AT THE PRECISION
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],{(1){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-1:0],{(9){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h33,6'h32,6'h31,6'h30,6'h2f,6'h2e,6'h2d,6'h2c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-1:0],{(5){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-9:0],{(9+8){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h2b,6'h2a,6'h29,6'h28,6'h27,6'h26,6'h25,6'h24:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-9:0],{(13){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-17:0],{(9+16){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h23,6'h22,6'h21,6'h20,6'h1f,6'h1e,6'h1d,6'h1c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-17:0],{(21){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-25:0],{(9+24){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h1b,6'h1a,6'h19,6'h18,6'h17,6'h16,6'h15,6'h14:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-25:0],{(29){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-33:0],{(9+32){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h13,6'h12,6'h11,6'h10,6'h0f,6'h0e,6'h0d,6'h0c:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-33:0],{(37){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-41:0],{(9+40){1'b1}} }; //Precision_ctl_S+1
                      end
                    6'h0b,6'h0a,6'h09,6'h08,6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64-41:0],{(45){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS-45:0],{(45){1'b1}} }; //Precision_ctl_S+1
                      end
                    default:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP64+3:0],{(1){1'b0}}}; //+3
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+8:1],{(1){1'b1}}}; //+3
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16)
              // 2'b10:
                begin
                  always_comb
                  begin
                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+5:0],{(C_MANT_FP64-C_MANT_FP16-1){1'b0}} }; //+5
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+5
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+8:5],1'b1}; //+4
                      end
                    6'h0a,6'h09,6'h08,6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+1:1],{(C_MANT_FP64-C_MANT_FP16+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:1],{(8){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16+5:0],{(C_MANT_FP64-C_MANT_FP16-1){1'b0}} }; //+5
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+5
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
                end
            else if (FpFormat == fpnew_pkg_snax::FP16ALT) 
              // 2'b11:
                begin
                  always_comb
                  begin

                  case (PRECISION_CTRL)
                    6'b00:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                    6'h07,6'h06:
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT:0],{(C_MANT_FP64-C_MANT_FP16ALT+4){1'b0}} }; //Precision_ctl_S+1
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS:0],{(4){1'b1}} }; //Precision_ctl_S+1
                      end
                    default :
                      begin
                        // Mant_result_prenorm_DO = {Quotient_DP[C_MANT_FP16ALT+4:0],{(C_MANT_FP64-C_MANT_FP16ALT){1'b0}} }; //+4
                        // Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:0]}; //+4
                        Mant_result_prenorm_DO = {Quotient_DP[MAN_BITS+4:1],1'b1}; //+4
                      end
                  endcase
                end
            // endcase
          end
        end
      endgenerate
//////////////////////eight iteration units,end///////////////////////////////////////



// resultant exponent
  //  logic   [C_EXP_FP64+1:0]    Exp_result_prenorm_DN,Exp_result_prenorm_DP;

  //  logic   [C_EXP_FP64+1:0]                                Exp_add_a_D;
  //  logic   [C_EXP_FP64+1:0]                                Exp_add_b_D;
  //  logic   [C_EXP_FP64+1:0]                                Exp_add_c_D;

   logic   [EXP_BITS+1:0]    Exp_result_prenorm_DN,Exp_result_prenorm_DP;

   logic   [EXP_BITS+1:0]                                Exp_add_a_D;
   logic   [EXP_BITS+1:0]                                Exp_add_b_D;
   logic   [EXP_BITS+1:0]                                Exp_add_c_D;

  // integer                                                 C_BIAS_AONE, C_HALF_BIAS;
  // always_comb
  //   begin  //
  //     case (Format_sel_S)
  //       2'b00:
  //         begin
  //           C_BIAS_AONE =C_BIAS_AONE_FP32;
  //           C_HALF_BIAS =C_HALF_BIAS_FP32;
  //         end
  //       2'b01:
  //         begin
  //           C_BIAS_AONE =C_BIAS_AONE_FP64;
  //           C_HALF_BIAS =C_HALF_BIAS_FP64;
  //         end
  //       2'b10:
  //         begin
  //           C_BIAS_AONE =C_BIAS_AONE_FP16;
  //           C_HALF_BIAS =C_HALF_BIAS_FP16;
  //         end
  //       2'b11:
  //         begin
  //           C_BIAS_AONE =C_BIAS_AONE_FP16ALT;
  //           C_HALF_BIAS =C_HALF_BIAS_FP16ALT;
  //         end
  //       endcase
  //   end


  integer                                                 C_BIAS_AONE, C_HALF_BIAS;
  generate
    begin  //
      if (FpFormat == fpnew_pkg_snax::FP32) 
          begin
            assign C_BIAS_AONE =C_BIAS_AONE_FP32;
            assign C_HALF_BIAS =C_HALF_BIAS_FP32;
          end
      else if (FpFormat == fpnew_pkg_snax::FP64) 
          begin
            assign C_BIAS_AONE =C_BIAS_AONE_FP64;
            assign C_HALF_BIAS =C_HALF_BIAS_FP64;
          end
      else if (FpFormat == fpnew_pkg_snax::FP16) 
          begin
            assign C_BIAS_AONE =C_BIAS_AONE_FP16;
            assign C_HALF_BIAS =C_HALF_BIAS_FP16;
          end
      else if (FpFormat == fpnew_pkg_snax::FP16ALT) 
          begin
            assign C_BIAS_AONE =C_BIAS_AONE_FP16ALT;
            assign C_HALF_BIAS =C_HALF_BIAS_FP16ALT;
          end   
    end
  endgenerate

//For division, exponent=(Exp_a_D-LZ1)-(Exp_b_D-LZ2)+BIAS
//For square root, exponent=(Exp_a_D-LZ1)/2+(Exp_a_D-LZ1)%2+C_HALF_BIAS
//For exponent, in preprorces module, (Exp_a_D-LZ1) and (Exp_b_D-LZ2) have been processed with the corresponding process for denormal numbers.

  // assign Exp_add_a_D = {Sqrt_start_dly_S?{Exp_num_DI[C_EXP_FP64],Exp_num_DI[C_EXP_FP64],Exp_num_DI[C_EXP_FP64],Exp_num_DI[C_EXP_FP64:1]}:{Exp_num_DI[C_EXP_FP64],Exp_num_DI[C_EXP_FP64],Exp_num_DI}};
  // assign Exp_add_b_D = {Sqrt_start_dly_S?{1'b0,{C_EXP_ZERO_FP64},Exp_num_DI[0]}:{~Exp_den_DI[C_EXP_FP64],~Exp_den_DI[C_EXP_FP64],~Exp_den_DI}};
  // assign Exp_add_c_D = {Div_start_dly_S?{{C_BIAS_AONE}}:{{C_HALF_BIAS}}};
  // assign Exp_result_prenorm_DN  = (Start_dly_S)?{Exp_add_a_D + Exp_add_b_D + Exp_add_c_D}:Exp_result_prenorm_DP;

  // localparam logic BIAS = fpnew_pkg_snax::bias(FpFormat);
  // localparam logic HALF_BIAS = (fpnew_pkg_snax::half_bias(FpFormat));

  assign Exp_add_a_D = {Exp_num_DI[EXP_BITS],Exp_num_DI[EXP_BITS],Exp_num_DI};
  assign Exp_add_b_D = {~Exp_den_DI[EXP_BITS],~Exp_den_DI[EXP_BITS],~Exp_den_DI}; // 2's complement 
  assign Exp_add_c_D = {Div_start_dly_S?{{C_BIAS_AONE}}:{{C_HALF_BIAS}}}; // Add the bias 
  assign Exp_result_prenorm_DN  = (Start_dly_S)?{Exp_add_a_D + Exp_add_b_D + Exp_add_c_D}:Exp_result_prenorm_DP;


  always_ff @(posedge Clk_CI, negedge Rst_RBI)
   begin
      if(~Rst_RBI)
        begin
          Exp_result_prenorm_DP <= '0;
        end
      else
        begin
          Exp_result_prenorm_DP<=  Exp_result_prenorm_DN;
        end
   end

  assign Exp_result_prenorm_DO = Exp_result_prenorm_DP;

endmodule
