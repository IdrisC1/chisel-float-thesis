module fp_div #(
  // FPU configuration
  parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, // determine how precise/how many iterations needed // Full precision as default
  // Datatype
  parameter fpnew_pkg_snax::fp_format_e FpFormat   = fpnew_pkg_snax::fp_format_e'(2),  //FP16 
  parameter logic [2:0] Iteration_unit_num_S  = 3'b011, //Default 4 
  parameter int unsigned ROM_ADDR_BITS = 8, //Number of bits in ROM
  parameter int unsigned GUARD_BITS = 11, //Number of guard bits to use in calculation

  // Round mode
  // parameter fpnew_pkg_snax::roundmode_e RM_SI = fpnew_pkg_snax::RNE
  parameter logic [C_RM-1:0] RM_SI = 3'h0,

  parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
  parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
  parameter int unsigned WIDTH = fpnew_pkg_snax::fp_width(FpFormat)
) (
    input  logic clk,
    input  logic rst_ni,
    input  logic div_valid,
    input  logic [WIDTH-1:0] operand_a_DI,
    input  logic [WIDTH-1:0] operand_b_DI,
    input  logic Kill_SI,
    output logic [WIDTH-1:0] result_DO,
    output logic [4:0] unit_status,
    output logic unit_ready,
    output logic unit_done
); 
  div_sqrt_top_mvp  #(
    .FpFormat (FpFormat),
    .PRECISION_CTRL (PRECISION_CTRL),
    // .Iteration_unit_num_S (Iteration_unit_num_S),
    .RM_SI    (RM_SI),
    .ROM_ADDR_BITS (ROM_ADDR_BITS),
    .GUARD_BITS (GUARD_BITS)

    ) i_divsqrt_lei (
   .clk           ( clk                               ),
   .Rst_RBI          ( rst_ni                              ),
   .Div_start_SI     ( div_valid                           ),
   .Operand_a_DI     ( operand_a_DI              ),
  //  .Operand_a_DI     ( 32'b01000001001000000000000000000000), // 10 in fp32               
   .Operand_b_DI     ( operand_b_DI                ),
  // .Operand_b_DI      ( 32'b01000000101000000000000000000000), // 5 in fp32
  //  .Kill_SI          ( flush_i | reg_ena_i[NUM_INP_REGS-1] ),
   .Kill_SI          ( Kill_SI ),
   .Result_DO        ( result_DO                         ),
   .Fflags_SO        ( unit_status                         ),
   .Ready_SO         ( unit_ready                          ),
   .Done_SO          ( unit_done                           )
  );
endmodule 

