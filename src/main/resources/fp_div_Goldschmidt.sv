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


endmodule;
//This file was partially written with an LLM (Gemini 3 from Google ) and adapted afterwards by Idris Christiaensen
module param_goldschmidt_optimized #(
    parameter int ROM_ADDR_BITS = 8,
    parameter int GUARD_BITS    = 3 // Extra bits for rounding accuracy

  parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
  parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, // Full precision as default
  parameter int nb_bits = 4, //Determine the number of iterations -> less needs larger LUT 8-> 128 Bytes
   
//   parameter logic [2:0] Iteration_unit_num_S  = 3'b011, //Default 4 (encoded in 3 bits)

  parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
  parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
  parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)
)(
    


  //Input
   input logic        clk,
   input logic        rst_n,
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

input  logic        clk,
    input  logic        rst_n,
    input  logic [63:0] dividend, 
    input  logic [63:0] divisor,
    output logic [63:0] quotient_packed

    // =========================================================================
    // 1. Bit Width Calculation
    // =========================================================================
    // IEEE 754 Double has 53 bits of Significand (1.xxxxx...)
    // We use Fixed Point format: Q2.F (2 Integer bits, F Fractional bits)
    // 2 Integer bits allows us to represent "2.0" cleanly.
    localparam int SIG_BITS  = 53; 
    localparam int FRAC_BITS = (SIG_BITS - 1) + GUARD_BITS; // 52 + 3 = 55
    localparam int WIDTH     = 2 + FRAC_BITS;               // 2 + 55 = 57 bits
    
    // Convergence Calculation
    function int calc_needed_stages(int start_bits);
        int bits;
        int stages;
        bits = start_bits;
        stages = 0;
        while (bits < SIG_BITS) begin
            bits = bits * 2;
            stages = stages + 1;
        end
        return stages;
    endfunction

    localparam int NUM_STAGES = calc_needed_stages(ROM_ADDR_BITS);
    localparam int ROM_DEPTH  = 1 << ROM_ADDR_BITS;

    // =========================================================================
    // 2. Unpack Inputs & Align to Internal Fixed Point
    // =========================================================================
    typedef struct packed {
        logic        sign;
        logic [10:0] exp;
        logic [51:0] sig;
    } float64_t;

    float64_t div_u, dvr_u;
    assign div_u = dividend;
    assign dvr_u = divisor;

    // =========================================================================
    // 3. Optimized ROM (Width adapted to logic)
    // =========================================================================
    logic [WIDTH-1:0] rcp_rom [0 : ROM_DEPTH-1];
    
    initial begin
        real x, inv;
        logic [WIDTH-1:0] val;
        // Pre-calculate the scale factor for Fixed Point
        // 1.0 in our format is represented as 2^FRAC_BITS
        real scale = (2.0**FRAC_BITS); 

        for (int i = 0; i < ROM_DEPTH; i++) begin
            x = 1.0 + (real'(i) / real'(ROM_DEPTH));
            inv = 1.0 / x;
            val = logic'(inv * scale); 
            rcp_rom[i] = val;
        end
    end

    logic [WIDTH-1:0] f0_val;
    assign f0_val = rcp_rom[dvr_u.sig[51 -: ROM_ADDR_BITS]];

    // =========================================================================
    // 4. Pipeline Signals (Now using WIDTH, not 64)
    // =========================================================================
    logic [WIDTH-1:0] n_pipe [0 : NUM_STAGES];
    logic [WIDTH-1:0] d_pipe [0 : NUM_STAGES];
    logic [WIDTH-1:0] f_pipe [0 : NUM_STAGES];
    
    // Metadata Delay
    logic [NUM_STAGES:0]       sign_pipe;
    logic [NUM_STAGES:0][10:0] exp_pipe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_pipe[0]    <= '0;
            d_pipe[0]    <= '0;
            f_pipe[0]    <= '0;
            sign_pipe[0] <= '0;
            exp_pipe[0]  <= '0;
        end else begin
            // Convert IEEE Sig (1.52) to Fixed Point (2.55)
            // IEEE: 1.xxxxx
            // Fixed: 01.xxxxx...000 (padded with 0s for guard bits)
            // We prepend '01' (representing 1.0) and pad the LSBs.
            n_pipe[0] <= {2'b01, div_u.sig, {GUARD_BITS{1'b0}}};
            d_pipe[0] <= {2'b01, dvr_u.sig, {GUARD_BITS{1'b0}}};
            f_pipe[0] <= f0_val;
            
            sign_pipe[0] <= div_u.sign ^ dvr_u.sign;
            exp_pipe[0]  <= (div_u.exp - dvr_u.exp) + 11'd1023;
        end
    end

    // =========================================================================
    // 5. Generated Pipeline
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_STAGES; i++) begin : gen_stages
            goldschmidt_stage_opt #(
                .WIDTH(WIDTH), 
                .FRAC_BITS(FRAC_BITS)
            ) stage_inst (
                .clk   (clk),
                .rst_n (rst_n),
                .n_in  (n_pipe[i]),
                .d_in  (d_pipe[i]),
                .f_in  (f_pipe[i]),
                .n_out (n_pipe[i+1]),
                .d_out (d_pipe[i+1]),
                .f_out (f_pipe[i+1])
            );
        end
    endgenerate

    // Delay Line Logic
    always_ff @(posedge clk) begin
        for (int k = 0; k < NUM_STAGES; k++) begin
             sign_pipe[k+1] <= sign_pipe[k];
             exp_pipe[k+1]  <= exp_pipe[k];
        end
    end

    // =========================================================================
    // 6. Final Output (Converting back to IEEE)
    // =========================================================================
    float64_t quo_u;
    
    always_comb begin
        // The result is in Fixed Point Q2.FRAC
        // Ideally it looks like 01.xxxxx (Normalized)
        // We drop the top 2 integer bits and the bottom Guard bits.
        quo_u.sig  = n_pipe[NUM_STAGES][FRAC_BITS-1 -: 52]; 
        quo_u.exp  = exp_pipe[NUM_STAGES];
        quo_u.sign = sign_pipe[NUM_STAGES];
    end

    assign quotient_packed = quo_u;

endmodule

// =============================================================================
// Helper: Width-Parametrized Stage
// =============================================================================
module goldschmidt_stage_opt #(
    parameter int WIDTH = 57,
    parameter int FRAC_BITS = 55
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] n_in,
    input  logic [WIDTH-1:0] d_in,
    input  logic [WIDTH-1:0] f_in,
    output logic [WIDTH-1:0] n_out,
    output logic [WIDTH-1:0] d_out,
    output logic [WIDTH-1:0] f_out
);
    // Multiplication Result is 2*WIDTH
    logic [2*WIDTH-1:0] n_mult_full;
    logic [2*WIDTH-1:0] d_mult_full;
    
    logic [WIDTH-1:0]   n_sliced, d_sliced;
    logic [WIDTH-1:0]   f_next_comb;

    // Constant for 2.0 in our Fixed Point format
    // If format is Q2.55, 1.0 is bit 55. 2.0 is bit 56.
    localparam logic [WIDTH-1:0] TWO_FIXED = (1 << (FRAC_BITS + 1));

    always_comb begin
        n_mult_full = n_in * f_in;
        d_mult_full = d_in * f_in;
        
        // BIT SLICING EXPLANATION:
        // Input:   Q2.55 * Q2.55 = Q4.110 (Total 114 bits)
        // We want: Q2.55 result.
        // The binary point in the full product is at bit 110.
        // We want to keep 55 bits below the point and 2 above.
        // So we keep bits [110 + 1 : 110 - 55].
        n_sliced = n_mult_full[2*FRAC_BITS + 1 : FRAC_BITS];
        d_sliced = d_mult_full[2*FRAC_BITS + 1 : FRAC_BITS];
        
        // Convergence: F = 2.0 - D
        f_next_comb = TWO_FIXED - d_sliced;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_out <= '0; d_out <= '0; f_out <= '0;
        end else begin
            n_out <= n_sliced;
            d_out <= d_sliced;
            f_out <= f_next_comb;
        end
    end
endmodule
