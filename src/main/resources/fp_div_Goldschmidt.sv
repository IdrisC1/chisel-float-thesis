module fp_div_Goldschmidt # (
  parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
  parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, // Full precision as default
  parameter int nb_bits = 4, //Determine the number of iterations -> less needs larger LUT 8-> 128 Bytes
   
//   parameter logic [2:0] Iteration_unit_num_S  = 3'b011, //Default 4 (encoded in 3 bits)

  parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
  parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
  parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)

)

  (//Input
   input logic                                        Clk_CI,
   input logic                                        Rst_RBI,
   input logic                                        Div_start_SI ,
   input logic                                        Start_SI,
   input logic                                        Kill_SI,
   input logic                                        Special_case_SBI,
   input logic                                        Special_case_dly_SBI,
   // Inputs for division
   input logic [MAN_BITS-1:0]                           Numerator_DI,
   input logic [EXP_BITS-1:0]                           Exp_num_DI, //exponent of numerator
   input logic [MAN_BITS-1:0]                           Denominator_DI, 
   input logic [EXP_BITS-1:0]                           Exp_den_DI, // exponent of denominator


   output logic                                       Div_start_dly_SO ,
   output logic                                       Div_enable_SO,
   output logic                                       Ready_SO, //Ready to get new input? 
   output logic                                       Done_SO,

   output logic [MAN_BITS+4:0]                        Mant_result_prenorm_DO,
   output logic [EXP_BITS+1:0]                        Exp_result_prenorm_DO
);
localparam int nb_iterations  = ($log(64) / $log(nb_bits));
logic [nb_bits-1:0]  lutIdx;
lutIdx = Denominator_DI[MAN_BITS-1:MAN_BITS-1-nb_bits];

logic [(2**nb_bits)][] first_bits 






















endmoduel
