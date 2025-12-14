// module fp_div_Goldschmidt # (
//   parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
//   parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, // Full precision as default
//   parameter int nb_bits = 4, //Determine the number of iterations -> less needs larger LUT 8-> 128 Bytes
   
// //   parameter logic [2:0] Iteration_unit_num_S  = 3'b011, //Default 4 (encoded in 3 bits)

//   parameter int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
//   parameter int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat),
//   parameter int unsigned WIDTH    = fpnew_pkg_snax::fp_width(FpFormat)

// )

//   (//Input
//    input logic                                        Clk_CI,
//    input logic                                        Rst_RBI,
//    input logic                                        Div_start_SI ,
//    input logic                                        Start_SI,
//    input logic                                        Kill_SI,
//    input logic                                        Special_case_SBI,
//    input logic                                        Special_case_dly_SBI,
//    // Inputs for division
//    input logic [MAN_BITS-1:0]                           Numerator_DI,
//    input logic [EXP_BITS-1:0]                           Exp_num_DI, //exponent of numerator
//    input logic [MAN_BITS-1:0]                           Denominator_DI, 
//    input logic [EXP_BITS-1:0]                           Exp_den_DI, // exponent of denominator


//    output logic                                       Div_start_dly_SO ,
//    output logic                                       Div_enable_SO,
//    output logic                                       Ready_SO, //Ready to get new input? 
//    output logic                                       Done_SO,

//    output logic [MAN_BITS+4:0]                        Mant_result_prenorm_DO,
//    output logic [EXP_BITS+1:0]                        Exp_result_prenorm_DO
// );
// localparam int nb_iterations  = ($log(64) / $log(nb_bits));
// logic [nb_bits-1:0]  lutIdx;
// lutIdx = Denominator_DI[MAN_BITS-1:MAN_BITS-1-nb_bits];

// logic [(2**nb_bits)][] first_bits 


// endmodule;
//This file was partially written with an LLM (Gemini 3 from Google ) and adapted afterwards by Idris Christiaensen


// fp_div_Goldschmidt.sv
// Fully Pipelined Goldschmidt Divider
// Throughput: 1 instruction per cycle
// Latency: Dependent on ROM_ADDR_BITS (Calculated automatically)

module fp_div_Goldschmidt #(
    parameter fpnew_pkg_snax::fp_format_e FpFormat = fpnew_pkg_snax::FP32,
    parameter int ROM_ADDR_BITS = 5,  // Larger ROM = Fewer Pipeline Stages
    parameter int GUARD_BITS    = 11,  // Internal precision buffer
    // parameter logic [C_PC-1:0] PRECISION_CTRL = 'h00, 
    
    // Extracted parameters
    localparam int unsigned EXP_BITS = fpnew_pkg_snax::exp_bits(FpFormat),
    localparam int unsigned MAN_BITS = fpnew_pkg_snax::man_bits(FpFormat)
)(
    input  logic                   clk,
    input  logic                   rst_ni,
    input  logic                   kill_i,      // Flush pipeline
    input  logic                   start_i,     // Valid input

    // Input Data (Normalized from preprocess_mvp)
    input  logic [MAN_BITS:0]      mant_a_i,    // Numerator (includes hidden bit)
    input  logic [MAN_BITS:0]      mant_b_i,    // Denominator (includes hidden bit)
    input  logic [EXP_BITS:0]      exp_a_i,
    input  logic [EXP_BITS:0]      exp_b_i,

    // Passthrough Control Signals (Metadata to travel with pipeline)
    // input  logic [2:0]             rm_i,        // Rounding Mode
    input  logic                   sign_z_i,
    // input  logic                   special_case_i,
    input  logic                   inf_a_i, inf_b_i,
    input  logic                   zero_a_i, zero_b_i,
    input  logic                   nan_a_i, nan_b_i, snan_i,

    // Outputs
    output logic                   valid_o,
    output logic [MAN_BITS+4:0]    mant_res_o,  // Result to Normalizer
    output logic [EXP_BITS+1:0]    exp_res_o,   // Result Exponent

    // Delayed Metadata outputs
    // output logic [2:0]             rm_o,
    output logic                   sign_z_o,
    // output logic                   special_case_o,
    output logic                   inf_a_o, inf_b_o,
    output logic                   zero_a_o, zero_b_o,
    output logic                   nan_a_o, nan_b_o, snan_o
);

    // =========================================================================
    // 1. Bit Width & Pipeline Depth Calculation
    // =========================================================================
    // We use Fixed Point format: Q2.F (2 Integer bits, F Fractional bits)
    // 2 Integer bits allows us to represent "2.0" cleanly.
    localparam int FRAC_BITS = MAN_BITS + GUARD_BITS; 
    localparam int WIDTH     = 2 + FRAC_BITS; 

    // Function to calculate needed stages for quadratic convergence
    function int calc_needed_stages(int start_bits);
        int bits;
        int stages;
        bits = start_bits;
        stages = 0;
        // Double precision until we exceed the target mantissa width
        while (bits < MAN_BITS + GUARD_BITS ) begin
            bits = bits * 2;
            stages = stages + 1;
        end

        return stages + 1; // add one extra cycle for truncation erros
    endfunction

    localparam int NUM_STAGES = calc_needed_stages(ROM_ADDR_BITS);
    localparam int ROM_DEPTH  = 1 << ROM_ADDR_BITS;

    // =========================================================================
    // 2. ROM Generation (Initial Estimate of 1/D)
    // =========================================================================
    
    // Determine safe calculation width for 64-bit integer
    localparam int CALC_WIDTH   = (WIDTH > 64) ? 64 : WIDTH;
    localparam int SHIFT_AMOUNT = WIDTH - CALC_WIDTH;

    logic [WIDTH-1:0] rcp_rom [0 : ROM_DEPTH-1];

    initial begin
        real x, inv, scale, scaled_inv;
        longint unsigned val_int;
        
        // Scale factor uses the Safe CALC_WIDTH
        scale = $pow(2.0, CALC_WIDTH - 2);

        for (int i = 0; i < ROM_DEPTH; i++) begin
            x = 1.0 + ($itor(i) / $itor(ROM_DEPTH));
            inv = 1.0 / x;
            
            scaled_inv = inv * scale;
            
            // Round-to-nearest
            val_int = scaled_inv + 0.5; 
            
            // [FIX] Slicing is now guaranteed safe by localparams.
            // val_int is 64 bits. CALC_WIDTH is max 60.
            // We take the top bits and pad zeros at the bottom.
            rcp_rom[i] = {val_int[CALC_WIDTH-1:0], {SHIFT_AMOUNT{1'b0}}};
        end
    end

    logic [WIDTH-1:0] f0_val;
    // Use top bits of Denominator Mantissa for lookup (excluding hidden bit)
    // mant_b_i is [MAN_BITS ... 0]. 
    // MAN_BITS is hidden bit (always 1).
    // We want the MSBs of the fraction, which start at MAN_BITS-1.
    assign f0_val = rcp_rom[mant_b_i[MAN_BITS-1 -: ROM_ADDR_BITS]];

    // =========================================================================
    // 3. Pipeline Data Structures
    // =========================================================================
    logic [WIDTH-1:0] n_pipe [0 : NUM_STAGES]; //Pipeline of numerator
    logic [WIDTH-1:0] d_pipe [0 : NUM_STAGES]; //Pipeline of denominator
    logic [WIDTH-1:0] f_pipe [0 : NUM_STAGES]; //Pipeline of convergance factor F
    
    // Metadata Bundle definition for Shift Register
    typedef struct packed {
        logic       valid;
        logic [EXP_BITS+1:0] exp_diff; // Intermediate exponent
        // logic [2:0] rm;
        logic       sign_z;
        // logic       special;
        logic       inf_a, inf_b;
        logic       zero_a, zero_b;
        logic       nan_a, nan_b, snan;
    } metadata_t;

    metadata_t meta_pipe [0 : NUM_STAGES];

    // =========================================================================
    // 4. Stage 0: Setup / Packing
    // =========================================================================
    // Calculate initial exponent: ExpA - ExpB + Bias
    // Bias is handled in wrapper or here. Let's do raw subtract here + Bias AONE
    // Referenced from control_mvp: C_BIAS_AONE is used for Division.
    localparam int C_BIAS_AONE = fpnew_pkg_snax::bias(FpFormat) ; // Simplified approximation
    // Note: Accurate bias handling is usually done in the wrapper logic passed to Exp_in,
    // but here we calculate the difference.

    logic [EXP_BITS+1:0] exp_calc_d;
    // assign exp_calc_d = {1'b0, exp_a_i} - {1'b0, exp_b_i} + C_BIAS_AONE;
    assign exp_calc_d = $signed(exp_a_i) - $signed(exp_b_i) + $signed(C_BIAS_AONE);
    
    //For division, exponent=(Exp_a_D-LZ1)-(Exp_b_D-LZ2)+BIAS
    //For square root, exponent=(Exp_a_D-LZ1)/2+(Exp_a_D-LZ1)%2+C_HALF_BIAS
    //For exponent, in preprorces module, (Exp_a_D-LZ1) and (Exp_b_D-LZ2) have been processed with the corresponding process for denormal numbers.
    
    // logic [EXP_BITS+1:0] Exp_add_a_D, Exp_add_b_D, Exp_add_c_D;
    // assign Exp_add_a_D = {exp_a_i[EXP_BITS],exp_a_i[EXP_BITS],exp_a_i};
    // assign Exp_add_b_D = {~exp_b_i[EXP_BITS],~exp_b_i[EXP_BITS],~exp_b_i}; // 2's complement 
    // assign Exp_add_c_D = C_BIAS_AONE; // Add the bias 
    // assign exp_calc_d  = {Exp_add_a_D + Exp_add_b_D + Exp_add_c_D};

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            n_pipe[0]    <= '0;
            d_pipe[0]    <= '0;
            f_pipe[0]    <= '0;
            meta_pipe[0] <= '0;
        end else if (kill_i) begin
            meta_pipe[0].valid <= 1'b0;
        end else begin
            // Convert Input Mantissa (1.xxxxx) to Fixed Point (01.xxxxx...00)
            // mant_a_i includes hidden bit at MSB.
            n_pipe[0] <= {2'b01, mant_a_i[MAN_BITS-1:0], {GUARD_BITS{1'b0}}};
            d_pipe[0] <= {2'b01, mant_b_i[MAN_BITS-1:0], {GUARD_BITS{1'b0}}};
            f_pipe[0] <= f0_val;
            
            // Metadata
            meta_pipe[0].valid    <= start_i;
            meta_pipe[0].exp_diff <= exp_calc_d; //Calculated exponent differencens
            // meta_pipe[0].rm       <= rm_i;
            meta_pipe[0].sign_z   <= sign_z_i;
            // meta_pipe[0].special  <= special_case_i;
            meta_pipe[0].inf_a    <= inf_a_i;
            meta_pipe[0].inf_b    <= inf_b_i;
            meta_pipe[0].zero_a   <= zero_a_i;
            meta_pipe[0].zero_b   <= zero_b_i;
            meta_pipe[0].nan_a    <= nan_a_i;
            meta_pipe[0].nan_b    <= nan_b_i;
            meta_pipe[0].snan     <= snan_i;
        end
    end

    // =========================================================================
    // 5. Generate Pipeline Stages
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_STAGES; i++) begin : gen_stages
            goldschmidt_stage_opt #(
                .WIDTH(WIDTH), 
                .FRAC_BITS(FRAC_BITS)
            ) stage_inst (
                .clk   (clk),
                .rst_ni  (rst_ni),
                .kill_i  (kill_i),
                .n_in    (n_pipe[i]),
                .d_in    (d_pipe[i]),
                .f_in    (f_pipe[i]),
                .n_out   (n_pipe[i+1]),
                .d_out   (d_pipe[i+1]),
                .f_out   (f_pipe[i+1])
            );
            
            // Shift metadata
            always_ff @(posedge clk or negedge rst_ni) begin
                if(!rst_ni) meta_pipe[i+1] <= '0;
                else if(kill_i) meta_pipe[i+1].valid <= 1'b0;
                else meta_pipe[i+1] <= meta_pipe[i];
            end
        end
    endgenerate

    // =========================================================================
    // 6. Final Output Packing
    // =========================================================================
    // The result N converges to Quotient. format Q2.FRAC.
    // We need to map this to mant_res_o which expects [MAN_BITS+4:0] 
    // (Including rounding bits G, R, S).
    
    // logic [WIDTH-1:0] final_n;
    // assign final_n = n_pipe[NUM_STAGES];

    // always_comb begin
        // We take the fractional part. 
        // final_n is 01.xxxxx (if normalized).
        // mant_res_o expects {Hidden, Mantissa, G, R, S} approx.
        // We extract the relevant MSBs.
        
        // Take MSBs including the integer part (should be 01)
        // Adjust index based on alignment. 
        // High 56 bits roughly.
        // [FIX] Safe Assignment with Padding
        // We take the bits from the Hidden Bit (WIDTH-2) down to 0.
        // If the pipeline width is smaller than the required output (MAN_BITS+5),
        // we pad the LSBs with zeros.
        // The previous logic failed because if the condition was false, the final 'else' logic was wrong.
    
    // Safe index calculation: If we only have 27 bits (WIDTH-1) available, we extract 27 bits
    // and pad the LSB to meet the 28-bit output width.
    
    // Bits to extract: MIN(Width available, Width required)
    localparam int BITS_REQUIRED = MAN_BITS + 5;
    localparam int BITS_AVAILABLE_FROM_MSB = WIDTH - 1;

    // if (BITS_AVAILABLE_FROM_MSB >= BITS_REQUIRED) begin
    //      // This is the ideal case (e.g., GUARD_BITS=4, Width=29, BitsReq=28)
    //      // We extract the required length (28 bits) starting from the hidden bit (WIDTH-2)
    //      mant_res_o = final_n[WIDTH-2 :0  ]; 
    // end else begin
    //      // This block executes if GUARD_BITS=3 (Width=28). We have 27 bits available but need 28.
    //      // Action: Take all available bits (WIDTH-1) and pad LSB with zeros to meet 28 bits.
    //      mant_res_o = { final_n[WIDTH-2 : 0], {(BITS_REQUIRED - BITS_AVAILABLE_FROM_MSB){1'b0}} };
    // end


    // The Normalizer expects [MAN_BITS+4:0] with the Hidden Bit at the MSB.
    // Our 'final_n' has the Hidden Bit at 'WIDTH-2'.
    // We dynamically calculate the slice logic to ensure alignment.
    
// =========================================================================
    // 6. Final Output Packing
    // =========================================================================
    logic [WIDTH-1:0] final_n;
    assign final_n = n_pipe[NUM_STAGES];

    // // [FIX] Use GENERATE to handle width mismatch at elaboration time.
    // // This prevents the compiler from seeing negative replication counts.
    // generate
    //     // Calculate constants for clarity
    //     localparam int OUTPUT_WIDTH = MAN_BITS + 5; // Mantissa + Hidden + GRS
    //     localparam int AVAILABLE_BITS = WIDTH - 1; // Bits from Hidden Bit (WIDTH-2) down to 0

    //     if (AVAILABLE_BITS >= OUTPUT_WIDTH) begin : gen_slice
    //         // CASE A: We have enough bits. Just slice.
    //         // This branch is compiled when GUARD_BITS is High (e.g. 7)
    //         assign mant_res_o = {final_n[WIDTH-2 -: OUTPUT_WIDTH]};
    //     end else begin : gen_pad
    //         // CASE B: We are short bits. Pad with zeros.
    //         // This branch is compiled when GUARD_BITS is Low (e.g. 3 or 4)
    //         assign mant_res_o = {final_n[WIDTH-2 : 0], {(OUTPUT_WIDTH - AVAILABLE_BITS){1'b0}} };
    //     end
    // endgenerate
    // [CRITICAL FIX] Sticky Bit Propagation
    // We must OR all the bits we are dropping into the LSB of the output.


    generate
        localparam int OUTPUT_WIDTH = MAN_BITS + 5; // Hidden + Mant + GRS
        localparam int AVAILABLE_BITS = WIDTH - 1;  // Bits from Hidden down to 0

        if (AVAILABLE_BITS >= OUTPUT_WIDTH) begin : gen_slice
            // We have excess bits (e.g., GUARD_BITS is large)
            // Calculate indices
            localparam int MSB_INDEX = WIDTH - 2;
            localparam int LSB_INDEX = WIDTH - 2 - OUTPUT_WIDTH + 1;
            
            logic sticky_bit;
            assign sticky_bit = | final_n[LSB_INDEX - 1 : 0];

            // Assign Result: Top bits + (LSB | Sticky)
            assign mant_res_o = { 
                final_n[MSB_INDEX : LSB_INDEX + 1], 
                final_n[LSB_INDEX] | sticky_bit 
            };
        end else begin : gen_pad
            // We are short bits - all bits from final_n are used
            // No bits are dropped, so sticky bit is 0
            assign mant_res_o = {final_n[WIDTH-2 : 0], {(OUTPUT_WIDTH - AVAILABLE_BITS){1'b0}} };
        end
    endgenerate


    

    // -------------------------------------------------------------------------
    // Pass-through Signals (Keep this separate)
    // -------------------------------------------------------------------------
    always_comb begin
        exp_res_o      = meta_pipe[NUM_STAGES].exp_diff;
        valid_o        = meta_pipe[NUM_STAGES].valid;
        
        // rm_o           = meta_pipe[NUM_STAGES].rm;
        sign_z_o       = meta_pipe[NUM_STAGES].sign_z;
        // special_case_o = meta_pipe[NUM_STAGES].special;
        inf_a_o        = meta_pipe[NUM_STAGES].inf_a;
        inf_b_o        = meta_pipe[NUM_STAGES].inf_b;
        zero_a_o       = meta_pipe[NUM_STAGES].zero_a;
        zero_b_o       = meta_pipe[NUM_STAGES].zero_b;
        nan_a_o        = meta_pipe[NUM_STAGES].nan_a;
        nan_b_o        = meta_pipe[NUM_STAGES].nan_b;
        snan_o         = meta_pipe[NUM_STAGES].snan;
    end

endmodule

// Helper Module for Stages
module goldschmidt_stage_opt #(
    parameter int WIDTH = 57,
    parameter int FRAC_BITS = 55
)(
    input  logic             clk,
    input  logic             rst_ni,
    input  logic             kill_i,
    input  logic [WIDTH-1:0] n_in,
    input  logic [WIDTH-1:0] d_in,
    input  logic [WIDTH-1:0] f_in,
    output logic [WIDTH-1:0] n_out,
    output logic [WIDTH-1:0] d_out,
    output logic [WIDTH-1:0] f_out
);
    logic [2*WIDTH-1:0] n_mult_full;
    logic [2*WIDTH-1:0] d_mult_full;
    logic [WIDTH-1:0]   n_sliced, d_sliced;
    logic [WIDTH-1:0]   f_next_comb;
    localparam logic [WIDTH-1:0] TWO_FIXED = (1 << (FRAC_BITS + 1)); //represent 2.0

    always_comb begin
        // 1. Independent Multiplications
        n_mult_full = n_in * f_in;
        d_mult_full = d_in * f_in;
        
        // // 2. Fixed Point Slicing (Maintain Q2.F format)
        n_sliced = n_mult_full[2*FRAC_BITS + 1 : FRAC_BITS];
        d_sliced = d_mult_full[2*FRAC_BITS + 1 : FRAC_BITS];
        // n_sliced = n_mult_full[2*FRAC_BITS + 1 : FRAC_BITS] + n_mult_full[FRAC_BITS - 1];
        // d_sliced = d_mult_full[2*FRAC_BITS + 1 : FRAC_BITS] + d_mult_full[FRAC_BITS - 1];

        
        // 3. Convergence Factor: F = 2.0 - D
        f_next_comb = TWO_FIXED - d_sliced;
    end

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            n_out <= '0; d_out <= '0; f_out <= '0;
        end else if (kill_i) begin
            n_out <= '0; d_out <= '0; f_out <= '0;
        end else begin
            n_out <= n_sliced;
            d_out <= d_sliced;
            f_out <= f_next_comb;
        end
    end
endmodule







